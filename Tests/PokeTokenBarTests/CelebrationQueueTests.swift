import XCTest
@testable import PokeTokenBar

@MainActor
final class CelebrationQueueTests: XCTestCase {
    private let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

    private func names(_ ids: [Int]) -> [Int: [String: String]] {
        Dictionary(uniqueKeysWithValues: ids.map { ($0, ["en": "P\($0)", "ko": "포\($0)", "ja": "ポ\($0)"]) })
    }
    private var linear3: EvoLine {
        EvoLine(baseID: 1, tree: EvoNode(speciesID: 1, children: [EvoNode(speciesID: 2, children: [EvoNode(speciesID: 3, children: [])])]),
                rarity: .common, names: names([1, 2, 3]))
    }
    private func store(seed: UInt64 = 7) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-\(UUID().uuidString).json")
        return CompanionStore(provider: StubProvider(value: linear3), clock: { self.fixedNow },
                              fileURL: url, rng: SeededRNG(seed: seed))
    }
    private var stage0Threshold: Int { PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 0) }

    func testEveryLiveSurfacePlays() {
        XCTAssertEqual(CelebrationQueue.liveSurfaces(popoverOpen: true, floatingPetLive: true), [.popover, .floatingPet],
                       "popover open and pet shown: both play the head at the same time")
        XCTAssertEqual(CelebrationQueue.liveSurfaces(popoverOpen: false, floatingPetLive: true), [.floatingPet])
        XCTAssertEqual(CelebrationQueue.liveSurfaces(popoverOpen: true, floatingPetLive: false), [.popover])
        XCTAssertEqual(CelebrationQueue.liveSurfaces(popoverOpen: false, floatingPetLive: false), [])
    }

    /// Two surfaces on one item: the second joins at the first's start, the first finish releases the held
    /// notification once, and a second finish of the same id does nothing.
    func testSharedPlaybackStartsTogetherAndIsSeenOnce() async throws {
        let s = store()
        await s.hatch(baseID: 1)
        s.celebrations.items.forEach { s.finishCelebration(id: $0.id) }
        s.popoverOpen = true
        s.floatingPetLive = true
        let log = EventLog(s)
        s.applyUsage(stage0Threshold)
        let id = try XCTUnwrap(s.celebrations.items.first?.id)
        let t0 = Date(timeIntervalSince1970: 100)
        XCTAssertEqual(s.beginCelebration(id: id, on: .floatingPet, now: t0, reduced: false).startedAt, t0)
        let joined = s.beginCelebration(id: id, on: .popover, now: t0.addingTimeInterval(3), reduced: true)
        XCTAssertEqual(joined.startedAt, t0, "the popover joins the pet's sequence at the same instant")
        XCTAssertFalse(joined.reduced, "R2: and in the same version, though Low Power came on in between")
        XCTAssertEqual(s.celebrationPlayback?.surfaces, [.popover, .floatingPet])
        s.skipCelebration(id: id, startedAt: t0.addingTimeInterval(-4))
        XCTAssertEqual(s.celebrationPlayback?.startedAt, t0.addingTimeInterval(-4), "a skip moves the shared start")
        s.skipCelebration(id: id + 99, startedAt: t0)
        XCTAssertEqual(s.celebrationPlayback?.startedAt, t0.addingTimeInterval(-4), "another id: ignored")

        s.finishCelebration(id: id)
        s.finishCelebration(id: id)
        XCTAssertEqual(log.texts, [s.l.notifEvolveBody(from: "P1", to: "P2")], "released once")
        XCTAssertNil(s.celebrationPlayback)
        XCTAssertTrue(s.celebrations.items.isEmpty)
    }

    /// A surface leaving an item it did not finish: the other keeps the shared start; once nobody plays it, a
    /// later replay starts from 0.
    func testSharedPlaybackEndsWhenNoSurfacePlaysIt() async throws {
        let s = store()
        s.popoverOpen = true
        await s.hatch(baseID: 1)
        let id = try XCTUnwrap(s.celebrations.items.first?.id)
        let t0 = Date(timeIntervalSince1970: 100)
        s.floatingPetLive = true
        _ = s.beginCelebration(id: id, on: .popover, now: t0, reduced: false)
        _ = s.beginCelebration(id: id, on: .floatingPet, now: t0, reduced: false)
        s.celebrationStopped(id: id, on: .popover)
        XCTAssertEqual(s.celebrationPlayback?.startedAt, t0, "the pet keeps playing: no restart")
        s.celebrationStopped(id: id + 99, on: .floatingPet)
        XCTAssertNotNil(s.celebrationPlayback, "another id: ignored")
        s.celebrationStopped(id: id, on: .floatingPet)
        XCTAssertNil(s.celebrationPlayback)
        XCTAssertEqual(s.celebrations.items.map(\.id), [id], "stopped before the reveal: unseen")
        let later = t0.addingTimeInterval(60)
        XCTAssertEqual(s.beginCelebration(id: id, on: .popover, now: later, reduced: false).startedAt, later,
                       "replays from 0")
    }

    func testHatchThenEvolveQueueInOrder() async {
        let s = store()
        s.popoverOpen = true
        await s.hatch(baseID: 1)
        s.applyUsage(stage0Threshold)
        let kinds = s.celebrations.items.map(\.kind)
        guard kinds.count == 2, case .hatch(let to) = kinds[0], case .evolve(let from, let evolved) = kinds[1] else {
            return XCTFail("expected [hatch, evolve], got \(kinds)")
        }
        XCTAssertEqual(to.speciesID, 1)
        XCTAssertEqual(from.speciesID, 1)
        XCTAssertEqual(evolved.speciesID, 2)
        XCTAssertEqual(evolved.name, "P2")
    }

    func testDeferredNotificationWhenOwnerLive() async {
        let s = store()
        await s.hatch(baseID: 1)
        s.celebrations.items.forEach { s.finishCelebration(id: $0.id) }
        s.popoverOpen = true
        let before = s.latestEvent
        s.applyUsage(stage0Threshold)
        XCTAssertEqual(s.latestEvent, before, "notification waits for playback")
        guard let item = s.celebrations.items.first else { return XCTFail("evolve queued") }
        XCTAssertNotNil(item.deferred)
        s.finishCelebration(id: item.id)
        XCTAssertEqual(s.latestEvent?.text, s.l.notifEvolveBody(from: "P1", to: "P2"))
        XCTAssertEqual(s.displayState, .levelUp)
        XCTAssertTrue(s.celebrations.items.isEmpty)
    }

    func testImmediateNotificationWhenNoOwner() async {
        let s = store()
        await s.hatch(baseID: 1)
        s.applyUsage(stage0Threshold)
        XCTAssertEqual(s.latestEvent?.text, s.l.notifEvolveBody(from: "P1", to: "P2"))
        XCTAssertEqual(s.celebrations.items.count, 2, "popover catch-up still plays")
        XCTAssertTrue(s.celebrations.items.allSatisfy { $0.deferred == nil })
    }

    func testOwnerLossFlushesDeferredNotification() async {
        let s = store()
        await s.hatch(baseID: 1)
        s.celebrations.items.forEach { s.finishCelebration(id: $0.id) }
        s.popoverOpen = true
        let before = s.latestEvent
        s.applyUsage(stage0Threshold)
        XCTAssertEqual(s.latestEvent, before)
        s.popoverOpen = false
        XCTAssertEqual(s.latestEvent?.text, s.l.notifEvolveBody(from: "P1", to: "P2"))
        XCTAssertEqual(s.celebrations.items.count, 1)
        XCTAssertNil(s.celebrations.items.first?.deferred)
    }

    func testChainedEvolutionsQueueInOrder() async {
        let s = store()
        await s.hatch(baseID: 1)
        s.celebrations.items.forEach { s.finishCelebration(id: $0.id) }
        s.popoverOpen = true
        s.applyUsage(stage0Threshold + PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 1))
        let kinds = s.celebrations.items.map(\.kind)
        guard kinds.count == 2, case .evolve(_, let first) = kinds[0], case .evolve(_, let second) = kinds[1] else {
            return XCTFail("expected two evolves, got \(kinds)")
        }
        XCTAssertEqual(first.speciesID, 2)
        XCTAssertEqual(second.speciesID, 3)
        let firstItem = s.celebrations.items[0]
        s.finishCelebration(id: firstItem.id)
        XCTAssertEqual(s.latestEvent?.text, s.l.notifEvolveBody(from: "P1", to: "P2"), "only the first is announced")
        XCTAssertNotNil(s.celebrations.items.first?.deferred)
    }

    func testResetClearsQueue() async throws {
        let s = store()
        await s.hatch(baseID: 1)
        s.applyUsage(stage0Threshold)
        XCTAssertFalse(s.celebrations.items.isEmpty)
        var imported = CompanionState()
        imported.installBaselineSet = true
        let envelope = SaveEnvelope(format: SaveEnvelope.formatID, schema: SaveEnvelope.schemaVersion,
                                    appVersion: "2.5.7", exportedAt: Date(), sourceDevice: "Mac", state: imported)
        try s.applySave(envelope, todayTokensByProvider: [:], todayDate: "2026-11-20", hasUsageData: false)
        XCTAssertTrue(s.celebrations.items.isEmpty)
    }

    func testDittoRevealPlayableOnPopoverOnly() {
        var q = CelebrationQueue()
        let id = q.enqueue(.dittoReveal(shiny: false), deferred: nil)
        let item = q.items[0]
        XCTAssertTrue(item.isPlayable(on: .popover))
        XCTAssertFalse(item.isPlayable(on: .floatingPet))
        XCTAssertNil(q.next(for: .floatingPet))
        XCTAssertEqual(q.next(for: .popover)?.id, id)
        let subject = CelebrationSubject(speciesID: 1, form: nil, isShiny: false, name: "P1")
        q.enqueue(.hatch(to: subject), deferred: nil)
        XCTAssertEqual(q.next(for: .floatingPet)?.kind, .hatch(to: subject), "skips the Ditto reveal")
    }

    func testHatchDeferredWhenOwnerLive() async {
        let s = store()
        s.popoverOpen = true
        await s.hatch(baseID: 1)
        XCTAssertNil(s.latestEvent)
        guard let item = s.celebrations.items.first, case .hatch = item.kind else { return XCTFail("hatch queued") }
        XCTAssertNotNil(item.deferred)
        s.finishCelebration(id: item.id)
        XCTAssertNotNil(s.latestEvent)
        XCTAssertEqual(s.displayState, .levelUp)
    }

    func testFloatingPetLiveLossFlushesDeferred() async {
        let s = store()
        await s.hatch(baseID: 1)
        s.celebrations.items.forEach { s.finishCelebration(id: $0.id) }
        s.floatingPetLive = true
        let before = s.latestEvent
        s.applyUsage(stage0Threshold)
        XCTAssertEqual(s.latestEvent, before)
        XCTAssertNotNil(s.celebrations.items.first?.deferred)
        s.floatingPetLive = false
        XCTAssertEqual(s.latestEvent?.text, s.l.notifEvolveBody(from: "P1", to: "P2"))
        XCTAssertEqual(s.celebrations.items.count, 1)
        XCTAssertNil(s.celebrations.items.first?.deferred)
    }

    private func overflowStore(_ line: EvoLine, tokens: Int) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-\(UUID().uuidString).json")
        let s = CompanionStore(provider: StubProvider(value: line), clock: { self.fixedNow },
                               fileURL: url, rng: SeededRNG(seed: 11))
        s.popoverOpen = true
        s.update(todayTokensByProvider: ["test": 0], todayDate: "d1", monthTotal: 0, burnTier: .idle, limitWarning: false, hasUsageData: true)
        s.update(todayTokensByProvider: ["test": tokens], todayDate: "d1", monthTotal: 0, burnTier: .idle, limitWarning: false, hasUsageData: true)
        return s
    }

    func testInstantGraduateWithLiveOwnerDropsHatchAndAnnouncesIt() async {
        let line = EvoLine(baseID: 20, tree: EvoNode(speciesID: 20, children: []), rarity: .common, names: names([20]))
        let s = overflowStore(line, tokens: 800_000_000)
        let log = EventLog(s)
        await s.hatchIfNeeded()
        XCTAssertNil(s.state.active, "instant graduate")
        XCTAssertTrue(s.celebrations.items.isEmpty)
        XCTAssertEqual(log.texts, [s.l.notifHatchBody("P20"), s.l.notifGraduateBody("P20")],
                       "the hatch is announced first, the graduation last")
        XCTAssertEqual(s.latestEvent?.text, s.l.notifGraduateBody("P20"))
        XCTAssertEqual(s.justGraduated, "P20")
    }

    func testInstantGraduateDropsEvolveItemsQueuedAfterHatch() async {
        let line = EvoLine(baseID: 1, tree: EvoNode(speciesID: 1, children: [EvoNode(speciesID: 2, children: [])]),
                           rarity: .common, names: names([1, 2]))
        let s = overflowStore(line, tokens: 800_000_000)
        let log = EventLog(s)
        await s.hatchIfNeeded()
        XCTAssertNil(s.state.active, "evolved once, then graduated")
        XCTAssertTrue(s.celebrations.items.isEmpty, "the departed mon's evolve must not play")
        XCTAssertEqual(log.texts, [s.l.notifHatchBody("P1"), s.l.notifEvolveBody(from: "P1", to: "P2"),
                                   s.l.notifGraduateBody("P2")], "announced in the order they happened")
        XCTAssertEqual(s.latestEvent?.text, s.l.notifGraduateBody("P2"))
    }

    // MARK: Ordered events (a notice never overtakes a held notification)

    /// Every companion event the store records, in order.
    @MainActor
    private final class EventLog {
        private(set) var texts: [String] = []
        init(_ store: CompanionStore) { store.companionEventObserver = { [unowned self] in self.texts.append($0.text) } }
    }

    /// A hatched 1 whose hatch already played, the popover open, then enough usage for 1 → 2 → 3 and the graduation.
    private func graduatingStore() async -> (CompanionStore, EventLog) {
        let s = store()
        await s.hatch(baseID: 1)
        s.celebrations.items.forEach { s.finishCelebration(id: $0.id) }
        s.popoverOpen = true
        let log = EventLog(s)
        s.applyUsage(10_000_000_000)
        return (s, log)
    }

    func testGraduationWaitsBehindTheQueuedEvolutions() async {
        let (s, log) = await graduatingStore()
        XCTAssertNil(s.state.active, "graduated")
        XCTAssertEqual(log.texts, [], "the graduation must not overtake the evolutions still to play")
        XCTAssertNil(s.justGraduated, "no graduation line before the evolutions are seen")
        let ids = s.celebrations.items.map(\.id)
        XCTAssertEqual(ids.count, 2, "1 → 2 and 2 → 3 are still to play")

        s.finishCelebration(id: ids[0])
        XCTAssertEqual(log.texts, [s.l.notifEvolveBody(from: "P1", to: "P2")])
        XCTAssertNil(s.justGraduated)
        s.finishCelebration(id: ids[1])
        XCTAssertEqual(log.texts, [s.l.notifEvolveBody(from: "P1", to: "P2"), s.l.notifEvolveBody(from: "P2", to: "P3"),
                                   s.l.notifGraduateBody("P3")])
        XCTAssertEqual(s.latestEvent?.text, s.l.notifGraduateBody("P3"), "the latest event ends on the graduation")
        XCTAssertEqual(s.justGraduated, "P3", "the graduation line shows once released")
    }

    func testOwnerLossReleasesTheHeldGraduationInOrder() async {
        let (s, log) = await graduatingStore()
        XCTAssertEqual(log.texts, [])
        s.popoverOpen = false
        XCTAssertEqual(log.texts, [s.l.notifEvolveBody(from: "P1", to: "P2"), s.l.notifEvolveBody(from: "P2", to: "P3"),
                                   s.l.notifGraduateBody("P3")])
        XCTAssertEqual(s.justGraduated, "P3")
        XCTAssertEqual(s.celebrations.items.count, 2, "the sequences stay queued for a catch-up")
        XCTAssertTrue(s.celebrations.heldNotices.isEmpty)
    }

    func testGraduationWithNothingHeldGoesOutAtOnce() async {
        let s = store()
        await s.hatch(baseID: 1)
        let log = EventLog(s)
        s.applyUsage(10_000_000_000)   // no owner: every notification goes out as it happens
        XCTAssertEqual(log.texts.last, s.l.notifGraduateBody("P3"))
        XCTAssertEqual(s.justGraduated, "P3")
        XCTAssertTrue(s.celebrations.heldNotices.isEmpty)
    }

    // MARK: Generations (a new mon drops the previous one's sequences)

    func testNewHatchDropsTheGraduatedMonsCatchUp() async {
        let s = store()   // popover closed, pet off: everything waits for a catch-up
        await s.hatch(baseID: 1)
        s.applyUsage(10_000_000_000)   // 1 → 2, 2 → 3, graduated
        XCTAssertNil(s.state.active)
        XCTAssertEqual(s.celebrations.items.count, 3, "hatch and two evolves wait for the popover")
        await s.hatch(baseID: 1)   // the next egg hatches before the popover ever opened
        let kinds = s.celebrations.items.map(\.kind)
        guard kinds.count == 1, case .hatch = kinds[0] else {
            return XCTFail("only the new hatch may remain, got \(kinds)")
        }
    }

    func testNewHatchFlushesTheDroppedItemsHeldNotificationsInOrder() async {
        let (s, log) = await graduatingStore()
        XCTAssertEqual(log.texts, [])
        await s.hatch(baseID: 1)   // the popover never played them (e.g. it stayed on Settings)
        XCTAssertEqual(log.texts, [s.l.notifEvolveBody(from: "P1", to: "P2"), s.l.notifEvolveBody(from: "P2", to: "P3"),
                                   s.l.notifGraduateBody("P3")], "no notification is lost, in order")
        XCTAssertNil(s.justGraduated, "no graduation line under the new hatch")
        XCTAssertEqual(s.celebrations.items.count, 1)
        XCTAssertNotNil(s.celebrations.items.first?.deferred, "the new hatch holds its own notification")
        XCTAssertTrue(s.celebrations.heldNotices.isEmpty)
    }

    func testSaveImportFlushesHeldNotificationsBeforeClearing() async throws {
        let (s, log) = await graduatingStore()
        var imported = CompanionState()
        imported.installBaselineSet = true
        let envelope = SaveEnvelope(format: SaveEnvelope.formatID, schema: SaveEnvelope.schemaVersion,
                                    appVersion: "2.5.7", exportedAt: Date(), sourceDevice: "Mac", state: imported)
        try s.applySave(envelope, todayTokensByProvider: [:], todayDate: "2026-11-20", hasUsageData: false)
        XCTAssertTrue(s.celebrations.items.isEmpty)
        XCTAssertEqual(log.texts, [s.l.notifEvolveBody(from: "P1", to: "P2"), s.l.notifEvolveBody(from: "P2", to: "P3"),
                                   s.l.notifGraduateBody("P3")])
        XCTAssertNil(s.justGraduated, "an imported save starts without the old mon's lines")
    }

    func testTerminationFlushesHeldNotifications() async {
        let (s, log) = await graduatingStore()
        s.flushHeldNotifications()
        XCTAssertEqual(log.texts, [s.l.notifEvolveBody(from: "P1", to: "P2"), s.l.notifEvolveBody(from: "P2", to: "P3"),
                                   s.l.notifGraduateBody("P3")])
        XCTAssertTrue(s.celebrations.items.allSatisfy { $0.deferred == nil })
        XCTAssertTrue(s.celebrations.heldNotices.isEmpty)
    }

    /// A player can end after the queue it played from was cleared (save import): nothing to finish.
    func testFinishingAnItemNoLongerQueuedDoesNothing() async throws {
        let s = store()
        s.popoverOpen = true
        await s.hatch(baseID: 1)
        let id = try XCTUnwrap(s.celebrations.items.first?.id)
        var imported = CompanionState()
        imported.installBaselineSet = true
        try s.applySave(SaveEnvelope(format: SaveEnvelope.formatID, schema: SaveEnvelope.schemaVersion,
                                     appVersion: "2.5.7", exportedAt: Date(), sourceDevice: "Mac", state: imported),
                        todayTokensByProvider: [:], todayDate: "2026-11-20", hasUsageData: false)
        let log = EventLog(s)
        s.finishCelebration(id: id)
        XCTAssertEqual(log.texts, [], "already flushed by the import, never twice")
    }

    func testQueueRemovalOfUnknownIDsIsANoOp() {
        var q = CelebrationQueue()
        let subject = CelebrationSubject(speciesID: 1, form: nil, isShiny: false, name: "P1")
        let event = DeferredCompanionEvent(title: "t", body: "b", levelUpSeconds: 4)
        q.enqueue(.hatch(to: subject), deferred: event)
        XCTAssertEqual(q.remove(id: 99), [])
        XCTAssertEqual(q.removeFrom(id: 99), [])
        XCTAssertEqual(q.items.count, 1)
        XCTAssertEqual(q.removeGenerations(before: 0), [], "nothing older than generation 0")
        XCTAssertEqual(q.items.count, 1)
    }

    func testHeldNoticeWaitsForEveryEarlierHeldNotification() {
        var q = CelebrationQueue()
        let subject = CelebrationSubject(speciesID: 1, form: nil, isShiny: false, name: "P1")
        func event(_ body: String) -> DeferredCompanionEvent { DeferredCompanionEvent(title: "t", body: body, levelUpSeconds: 4) }
        XCTAssertFalse(q.hold(event("early")), "nothing held: send it now")
        let first = q.enqueue(.hatch(to: subject), deferred: event("hatch"))
        let second = q.enqueue(.evolve(from: subject, to: subject), deferred: event("evolve"))
        XCTAssertTrue(q.hold(event("graduated")))
        let third = q.enqueue(.evolve(from: subject, to: subject), deferred: event("later"))
        XCTAssertEqual(q.remove(id: second).map(\.body), ["evolve"], "the hatch still holds its notification")
        XCTAssertEqual(q.remove(id: first).map(\.body), ["hatch", "graduated"])
        XCTAssertEqual(q.remove(id: third).map(\.body), ["later"])
    }

    // MARK: Pass 2

    /// A store whose wallet can buy an egg, with a hatched 1 whose hatch already played.
    private func walletStore() async -> CompanionStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-\(UUID().uuidString).json")
        let json = "{\"installBaselineSet\":true,\"usedSinceInstall\":\(FreshEgg.price * 4),\"spentTokens\":0,"
            + "\"lastDate\":\"d\",\"dex\":[],\"collectedFinals\":[]}"
        try? Data(json.utf8).write(to: url)
        let s = CompanionStore(provider: StubProvider(value: linear3), clock: { self.fixedNow },
                               fileURL: url, rng: SeededRNG(seed: 7))
        await s.hatch(baseID: 1)
        s.celebrations.items.forEach { s.finishCelebration(id: $0.id) }
        return s
    }

    /// R5: buying an egg releases the companion; its queued sequences go with it, their held notifications first.
    func testBuyingAnEggDropsTheReleasedCompanionsQueue() async {
        let s = await walletStore()
        s.popoverOpen = true
        let log = EventLog(s)
        s.applyUsage(stage0Threshold)   // 1 → 2, held for the popover, which has not played it
        XCTAssertEqual(s.celebrations.items.count, 1)
        XCTAssertTrue(s.buyEgg(nil))
        XCTAssertTrue(s.celebrations.items.isEmpty, "the released companion's evolve no longer plays")
        XCTAssertEqual(log.texts, [s.l.notifEvolveBody(from: "P1", to: "P2")], "its notification is not lost")
    }

    /// R1 backstop: a shared start that is already over is never joined, whatever left it behind.
    func testAnOverStartIsNeverJoined() async throws {
        let s = store()
        s.popoverOpen = true
        s.floatingPetLive = true
        await s.hatch(baseID: 1)
        let id = try XCTUnwrap(s.celebrations.items.first?.id)
        let t0 = Date(timeIntervalSince1970: 100)
        _ = s.beginCelebration(id: id, on: .floatingPet, now: t0, reduced: false)   // the pet never reports back
        let late = t0.addingTimeInterval(10.5)   // hatch total = 10 s: that playback is over
        XCTAssertEqual(s.beginCelebration(id: id, on: .popover, now: late, reduced: false).startedAt, late,
                       "starts fresh: an over start would finish at once without being shown")
        let soon = late.addingTimeInterval(9.9)
        XCTAssertEqual(s.beginCelebration(id: id, on: .floatingPet, now: soon, reduced: false).startedAt, late,
                       "inside the total: joined")
        XCTAssertEqual(s.beginCelebration(id: id, on: .floatingPet, now: late.addingTimeInterval(4.6), reduced: true).startedAt,
                       late, "the stored version decides the total, not the joiner's")
        // An id that is not (or no longer) queued has no timeline to join: it always starts fresh.
        let gone = id + 99
        _ = s.beginCelebration(id: gone, on: .popover, now: t0, reduced: false)
        XCTAssertEqual(s.beginCelebration(id: gone, on: .floatingPet, now: t0.addingTimeInterval(1), reduced: false).startedAt,
                       t0.addingTimeInterval(1))
    }

    /// R1: a player that reaches its end when its surface is no longer live is a stop, not a finish, and ends
    /// that surface's registration (even when the liveness change did not, e.g. it registered while not live).
    func testAnEndOffALiveSurfaceIsAStop() async throws {
        let s = store()
        await s.hatch(baseID: 1)
        let id = try XCTUnwrap(s.celebrations.items.first?.id)
        _ = s.beginCelebration(id: id, on: .popover, now: Date(timeIntervalSince1970: 100), reduced: false)
        s.celebrationPlayerEnded(id: id, on: .popover)
        XCTAssertNil(s.celebrationPlayback)
        XCTAssertEqual(s.celebrations.items.map(\.id), [id], "never revealed while live: unseen")
        s.popoverOpen = true
        _ = s.beginCelebration(id: id, on: .popover, now: Date(timeIntervalSince1970: 200), reduced: false)
        s.celebrationPlayerEnded(id: id, on: .popover)
        XCTAssertTrue(s.celebrations.items.isEmpty, "live: finished")
    }

    /// R6: seen at the reveal. A stop after it finishes the item (once) unless another live surface still plays
    /// it; a stop before it leaves the item unseen.
    func testAStopAfterTheRevealFinishesTheItemOnce() async throws {
        for (name, reveal, otherLive, seen) in [("after the reveal, alone", true, false, true),
                                                ("before the reveal", false, false, false),
                                                ("after the reveal, the pet still plays", true, true, false)] {
            let s = store()
            await s.hatch(baseID: 1)
            s.celebrations.items.forEach { s.finishCelebration(id: $0.id) }
            s.popoverOpen = true
            s.floatingPetLive = otherLive
            let log = EventLog(s)
            s.applyUsage(stage0Threshold)
            let id = try XCTUnwrap(s.celebrations.items.first?.id)
            _ = s.beginCelebration(id: id, on: .popover, now: Date(timeIntervalSince1970: 100), reduced: false)
            if otherLive { _ = s.beginCelebration(id: id, on: .floatingPet, now: Date(timeIntervalSince1970: 100), reduced: false) }
            if reveal { s.celebrationRevealed(id: id) }
            s.popoverOpen = false   // closed: the store ends the popover's part itself
            XCTAssertEqual(s.celebrations.items.isEmpty, seen, name)
            XCTAssertEqual(log.texts.count, seen ? 1 : (otherLive ? 0 : 1), "\(name): notification")
            s.finishCelebration(id: id)   // a later end of the same item
            s.celebrationStopped(id: id, on: .floatingPet)
            XCTAssertLessThanOrEqual(log.texts.count, 1, "\(name): never released twice")
        }
    }

    /// R5: the evolve on screen when the egg is bought plays to its end; only its notification waits for it.
    func testBuyingAnEggKeepsTheSequenceOnScreen() async throws {
        let s = await walletStore()
        s.popoverOpen = true
        let log = EventLog(s)
        s.applyUsage(stage0Threshold)
        let id = try XCTUnwrap(s.celebrations.items.first?.id)
        _ = s.beginCelebration(id: id, on: .popover, now: Date(timeIntervalSince1970: 100), reduced: false)
        XCTAssertTrue(s.buyEgg(nil))
        XCTAssertEqual(s.celebrations.items.map(\.id), [id], "the one playing stays")
        XCTAssertEqual(log.texts, [], "its notification still waits for its end")
        s.celebrationPlayerEnded(id: id, on: .popover)
        XCTAssertTrue(s.celebrations.items.isEmpty)
        XCTAssertEqual(log.texts, [s.l.notifEvolveBody(from: "P1", to: "P2")])
    }
}
