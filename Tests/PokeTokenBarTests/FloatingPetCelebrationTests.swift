import AppKit
import ImageIO
import SwiftUI
import XCTest
@testable import PokeTokenBar

/// The floating pet plays hatch/evolve sequences live: ownership, pinned override, bubble, panel room,
/// cancel when not shown, click-to-skip and the egg's incubation tier.
/// Controller tests show a real panel briefly; its sprites come from a temporary `SpriteStore` holding
/// synthetic discs (PNG and one-frame GIF) for species 1–3 (no network, no real cache).
@MainActor
final class FloatingPetCelebrationTests: XCTestCase {
    private typealias C = FloatingPetController
    private typealias Subject = CompanionStore.RepresentativeSubject

    // MARK: Pure decisions

    func testIsLiveRequiresEnabledVisibleAwake() {
        for enabled in [false, true] {
            for visible in [false, true] {
                for awake in [false, true] {
                    for interactive in [false, true] {
                        XCTAssertEqual(C.isLive(enabled: enabled, panelVisible: visible, displayAwake: awake,
                                                sessionInteractive: interactive),
                                       enabled && visible && awake && interactive,
                                       "enabled \(enabled) visible \(visible) awake \(awake) interactive \(interactive)")
                    }
                }
            }
        }
    }

    /// `NSWindow.isVisible` stays true behind these, so the session state decides on its own.
    func testSessionIsInteractiveOnlyWhenSomeoneCanSeeThePet() {
        typealias S = C.SessionState
        XCTAssertTrue(C.sessionInteractive(S(), screensaverRunning: false, startNoticed: false))
        XCTAssertFalse(C.sessionInteractive(S(screenLocked: true), screensaverRunning: false, startNoticed: false),
                       "lock screen")
        XCTAssertFalse(C.sessionInteractive(S(), screensaverRunning: true, startNoticed: false), "screensaver")
        XCTAssertFalse(C.sessionInteractive(S(onConsole: false), screensaverRunning: false, startNoticed: false),
                       "switched-out user")
        XCTAssertFalse(C.sessionInteractive(S(), screensaverRunning: false, startNoticed: true),
                       "a start notification counts even if the system state lags behind it")
    }

    func testSessionNoticesThatEndAnInterruptionScheduleTheRecheck() {
        let ends: [C.SessionNotice] = [.unlocked, .screensaverStopped, .becameActive]
        let starts: [C.SessionNotice] = [.locked, .screensaverStarted, .resignedActive]
        XCTAssertTrue(ends.allSatisfy(\.endsInterruption))
        XCTAssertFalse(starts.contains(where: \.endsInterruption))
    }

    func testBubblePriority() {
        typealias Note = AgentActivitySummary.Note
        let critical = UsageStore.LimitAlert(key: "c", window: "Claude weekly", isCritical: true, utilization: 96)
        let warning = UsageStore.LimitAlert(key: "w", window: "Claude weekly", isCritical: false, utilization: 81)
        let agent = AgentActivitySummary(done: Note(label: "b", message: nil))
        XCTAssertEqual(C.bubble(limitAlert: critical, agent: agent, celebration: "Huh?"), .limit(critical),
                       "a critical limit alert outranks the celebration")
        XCTAssertEqual(C.bubble(limitAlert: warning, agent: agent, celebration: "Huh?"), .celebration("Huh?"),
                       "the celebration outranks a warning")
        XCTAssertEqual(C.bubble(limitAlert: nil, agent: agent, celebration: "Huh?"), .celebration("Huh?"),
                       "the celebration outranks agents")
        XCTAssertEqual(C.bubble(limitAlert: warning, agent: agent, celebration: nil), .limit(warning))
        XCTAssertEqual(C.bubble(limitAlert: nil, agent: agent, celebration: nil), .agentDone(label: "b", message: nil))
        XCTAssertTrue(C.isShowingBubble(alertActive: false, heartsShowing: false, agent: AgentActivitySummary(),
                                        celebration: "Huh?"), "the celebration line needs the bubble headroom")
        XCTAssertFalse(C.heartsShowing(afterStrokeWithAlertActive: false, agent: AgentActivitySummary(),
                                       celebration: "Huh?"), "no hearts over a celebration line")
    }

    /// A celebration line is the pet speaking: no title, and it fits the bubble's two lines in every
    /// language without cutting the name of what it became. Iterates `allCases`, never a literal list.
    func testCelebrationBubbleIsUntitledAndFits() throws {
        let from = CelebrationSubject(speciesID: 9001, form: nil, isShiny: false, name: "Fletchinder")
        let to = CelebrationSubject(speciesID: 9002, form: nil, isShiny: false, name: "Crabominable")
        let lines: [(CelebrationText, CelebrationKind)] = [
            (.evolveAnnounce, .evolve(from: from, to: to)), (.evolveDone, .evolve(from: from, to: to)),
            (.hatchOh, .hatch(to: to)), (.hatchDone, .hatch(to: to)),
        ]
        for language in AppLanguage.allCases {
            let l = L(language)
            for (text, kind) in lines {
                let line = try XCTUnwrap(l.celebrationText(text, kind: kind), "\(language) \(text)")
                let content = C.bubbleContent(.celebration(line), l: l)
                XCTAssertEqual(content.title, "")
                XCTAssertFalse(content.isCritical)
                XCTAssertEqual(content.body, line, "\(language) \(text): cut to \(content.body)")
                let layout = C.measureSpeechBubbleLayout(title: content.title, body: content.body)
                XCTAssertFalse(layout.wouldTruncate)
                XCTAssertLessThanOrEqual(layout.size.height, C.bubbleHeadroom - 8,
                                         "\(language) \(text): fits above the pet (VStack spacing 8)")
                if text == .evolveDone || text == .hatchDone {
                    XCTAssertTrue(content.body.contains(to.name), "\(language) \(text): the result is named")
                }
            }
        }
    }

    func testPanelGrowsWhileCelebrating() {
        let margin = CelebrationStage.effectsMargin
        XCTAssertEqual(C.panelSize(petSize: 96, showingBubble: false, celebrating: true), NSSize(width: 152, height: 152))
        XCTAssertEqual(C.panelSize(petSize: 96, showingBubble: false), NSSize(width: 96, height: 96), "unchanged at rest")
        // With the bubble: its column is wider than the effects; the margin goes above and below.
        XCTAssertEqual(C.panelSize(petSize: 96, showingBubble: true, celebrating: true),
                       NSSize(width: C.bubbleMinWidth, height: 96 + C.bubbleHeadroom + 2 * margin))
        // A large pet is wider than the bubble column: the effects margin drives the width.
        XCTAssertEqual(C.panelSize(petSize: 384, showingBubble: true, celebrating: true),
                       NSSize(width: 384 + 2 * margin, height: 384 + C.bubbleHeadroom + 2 * margin))

        // Grounding: the same pet origin gives a panel whose pet box is where the resting pet was.
        let pet = NSPoint(x: 400, y: 200)
        for bubble in [false, true] {
            let size = C.panelSize(petSize: 96, showingBubble: bubble, celebrating: true)
            let origin = C.panelOrigin(petOrigin: pet, petSize: 96, panelSize: size, celebrating: true)
            XCTAssertEqual(origin.y, pet.y - margin, "the panel reaches the margin below the feet")
            XCTAssertEqual(origin.x + size.width / 2, pet.x + 48, "the pet stays centred")
            XCTAssertEqual(C.petOrigin(panelOrigin: origin, petSize: 96, panelSize: size, celebrating: true), pet)
        }
        let rest = C.panelSize(petSize: 96, showingBubble: true)
        XCTAssertEqual(C.panelOrigin(petOrigin: pet, petSize: 96, panelSize: rest).y, pet.y, "at rest: on the bottom edge")
    }

    func testDisplayedSubjectOverridesPinned() {
        let pikachu = Subject(speciesID: 25, isShiny: false)
        let hatched = CelebrationSubject(speciesID: 4, form: nil, isShiny: true, name: "Charmander")
        XCTAssertNil(C.displayedSubject(representative: pikachu, presentation: .egg).speciesID,
                     "the egg is shown while it hatches, even when Pikachu is pinned")
        XCTAssertEqual(C.displayedSubject(representative: pikachu, presentation: .subject(hatched)),
                       Subject(speciesID: 4, isShiny: true))
        XCTAssertEqual(C.displayedSubject(representative: pikachu, presentation: nil), pikachu)
    }

    func testCelebrationStepPlaysWheneverThePetIsLive() {
        let subject = CelebrationSubject(speciesID: 1, form: nil, isShiny: false, name: "P1")
        let head = PendingCelebration(id: 3, kind: .hatch(to: subject), deferred: nil)
        XCTAssertEqual(C.celebrationStep(petLive: true, head: head, playingID: nil), .play(head),
                       "live: plays, the popover open or not")
        XCTAssertEqual(C.celebrationStep(petLive: true, head: head, playingID: 3), .keep, "idempotent")
        XCTAssertEqual(C.celebrationStep(petLive: true, head: head, playingID: 2), .play(head),
                       "the queue moved on (seen on the popover): the new head replaces the old one")
        XCTAssertEqual(C.celebrationStep(petLive: true, head: nil, playingID: 3), .stop,
                       "seen on the popover first, or the queue was cleared, while the pet played")
        XCTAssertEqual(C.celebrationStep(petLive: true, head: nil, playingID: nil), .keep)
        XCTAssertEqual(C.celebrationStep(petLive: false, head: head, playingID: nil), .keep, "never starts while not live")
    }

    func testNoEggWobbleWhenMotionDisallowed() {
        XCTAssertNil(C.eggWobbleInterval(restingEgg: true, progress: 0.95, motionAllowed: false, panelVisible: true),
                     "Low Power / Reduce Motion")
        XCTAssertEqual(C.eggWobbleInterval(restingEgg: true, progress: 0.95, motionAllowed: true, panelVisible: true),
                       .seconds(3))
        XCTAssertNil(C.eggWobbleInterval(restingEgg: true, progress: 0.95, motionAllowed: true, panelVisible: false),
                     "hidden or asleep")
        XCTAssertNil(C.eggWobbleInterval(restingEgg: false, progress: 0.95, motionAllowed: true, panelVisible: true),
                     "a Pokémon (or the egg inside a playing hatch) does not wobble")
        XCTAssertNil(C.eggWobbleInterval(restingEgg: true, progress: 0.1, motionAllowed: true, panelVisible: true),
                     "an early egg stays still")
    }

    func testEggWobbleDriverRunsOneLoopPerInterval() async {
        var sleeps: [Duration] = [], wobbles = 0, cancelled = false
        let driver = EggWobbleDriver(sleep: { interval in
            sleeps.append(interval)
            guard sleeps.count > 2 else { return }
            do { try await Task.sleep(for: .seconds(3600)) } catch { cancelled = true; throw error }   // parked
        }, wobble: { wobbles += 1 })
        driver.update(every: .seconds(8))
        for _ in 0..<100 where wobbles < 2 { await Task.yield() }
        XCTAssertEqual(wobbles, 2, "one wobble per sleep")
        XCTAssertEqual(sleeps, [.seconds(8), .seconds(8), .seconds(8)])

        driver.update(every: .seconds(8))
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(sleeps.count, 3, "same interval: the running loop is kept, not restarted")

        driver.update(every: nil)
        XCTAssertNil(driver.interval, "stopped (hidden, asleep, hatched or no motion)")
        for _ in 0..<100 where !cancelled { await Task.yield() }
        XCTAssertTrue(cancelled, "the parked sleep is cancelled, not left behind")
        XCTAssertEqual(wobbles, 2, "no wobble after stop")
    }

    /// A released driver (a test controller, a rebuilt pet) cancels its sleeping loop instead of leaving it behind.
    func testEggWobbleDriverStopsItsLoopWhenReleased() async {
        var started = false, cancelled = false
        var driver: EggWobbleDriver? = EggWobbleDriver(sleep: { _ in
            started = true
            do { try await Task.sleep(for: .seconds(3600)) } catch { cancelled = true; throw error }
        }, wobble: {})
        driver?.update(every: .seconds(8))
        for _ in 0..<100 where !started { await Task.yield() }
        XCTAssertTrue(started)
        driver = nil
        for _ in 0..<100 where !cancelled { await Task.yield() }
        XCTAssertNil(driver)
        XCTAssertTrue(cancelled, "the parked sleep is cancelled with its driver")
    }

    func testPrayerCountBelongsToTheRestingEgg() {
        let egg = Subject(speciesID: nil, isShiny: false)
        XCTAssertEqual(C.hoverPrayerCount(subject: egg, presentation: nil, prayers: 12), 12)
        XCTAssertEqual(C.hoverPrayerCount(subject: egg, presentation: .egg, prayers: 12), 0)
        XCTAssertEqual(C.hoverPrayerCount(subject: Subject(speciesID: 25, isShiny: false), presentation: nil, prayers: 12), 0)
    }

    /// The untitled celebration bubble drops the title row; titled bubbles keep it.
    func testUntitledBubbleHasNoTitleRow() throws {
        func height(_ content: C.SpeechBubbleContent) throws -> CGFloat {
            let renderer = ImageRenderer(content: SpeechBubbleView(content: content))
            return try XCTUnwrap(renderer.nsImage).size.height
        }
        let titled = try height(C.SpeechBubbleContent(title: "Warning", body: "Claude weekly 81%", isCritical: false))
        let untitled = try height(C.bubbleContent(.celebration("Claude weekly 81%"), l: L(.en)))
        XCTAssertGreaterThan(titled - untitled, 10, "one bold 11 pt line less")
    }

    func testNudgeWobblesWithoutAParticle() {
        let burst = PrayerBurst()
        burst.nudge()
        XCTAssertEqual(burst.wobbleCount, 1)
        XCTAssertTrue(burst.particles.isEmpty)
    }

    func testHoverTooltipShowsTheEggTierWithoutSpoilers() {
        let l = L(.en)
        let egg = Subject(speciesID: nil, isShiny: false)
        XCTAssertEqual(C.eggTierLine(subject: egg, presentation: nil, eggProgress: 0.75, l: l),
                       EggIncubationTier.sounds.text(l))
        XCTAssertNil(C.eggTierLine(subject: Subject(speciesID: 25, isShiny: false), presentation: nil,
                                   eggProgress: 0.75, l: l), "a Pokémon has no incubation tier")
        // Mid-hatch the store is already past the egg (its progress belongs to the next egg): the hatching
        // egg reads as imminent, like the popover's pending-reveal column.
        XCTAssertEqual(C.eggTierLine(subject: egg, presentation: .egg, eggProgress: 0, l: l),
                       EggIncubationTier.imminent.text(l))

        let tooltip = FloatingPetView.hoverTooltip(todayTokens: 1_000, limitUtilization: nil, mode: .used, l: l,
                                                   eggLine: EggIncubationTier.sounds.text(l), prayers: 3)
        XCTAssertEqual(tooltip, l.floatingPetHoverTokensOnly(TokenFormatter.grouped(1_000))
                       + "\n" + EggIncubationTier.sounds.text(l) + "\n" + l.prayerHoverLine(3))
        XCTAssertFalse(tooltip.contains("Charmander"))
    }

    // MARK: Frame cap

    func testFloatingPetCapsTheStageAndThePopoverDoesNot() throws {
        XCTAssertGreaterThan(C.celebrationFrameInterval, 0, "an always-on surface keeps a named cap above 0")
        let player = CelebrationPlayer()
        XCTAssertNil(CelebrationStage(player: player, size: 76).minimumInterval, "popover stays uncapped")
        let stage = FloatingPetView.celebrationStage(player: player, size: 96, frameFloor: 0.4, spriteStore: .shared)
        XCTAssertEqual(stage.minimumInterval, C.celebrationFrameInterval)
        XCTAssertEqual(stage.minFrameDelay, 0.4, "the sprite inside keeps the user's GIF floor")

        // The schedule really spaces its entries by the cap.
        let start = Date(timeIntervalSince1970: 0)
        var capped = CelebrationStage.schedule(minimumInterval: C.celebrationFrameInterval)
            .entries(from: start, mode: .normal).makeIterator()
        let first = try XCTUnwrap(capped.next()), second = try XCTUnwrap(capped.next())
        XCTAssertEqual(second.timeIntervalSince(first), C.celebrationFrameInterval, accuracy: 1e-6)
    }

    // MARK: Controller

    // Real species ids: the evolution plan keeps only species the app has assets for.
    private static let names: [Int: [String: String]] = Dictionary(uniqueKeysWithValues: [1, 2, 3].map {
        ($0, ["en": "P\($0)", "ko": "포\($0)", "ja": "ポ\($0)"])
    })
    private static let line = EvoLine(
        baseID: 1,
        tree: EvoNode(speciesID: 1, children: [EvoNode(speciesID: 2, children: [EvoNode(speciesID: 3, children: [])])]),
        rarity: .common, names: names)

    private struct Fixture {
        let controller: FloatingPetController
        let store: UsageStore
        let companion: CompanionStore
        let defaults: UserDefaults
        let player: CelebrationPlayer
        let session: SessionBox
        let opened: () -> Int
        let cleanUp: () -> Void
    }

    /// The system session state the controller reads in `sync()`; tests flip it instead of locking the Mac.
    @MainActor
    final class SessionBox {
        var state = FloatingPetController.SessionState()
    }

    /// Lets a test decide when the player's sleeps return: they park until `release()`.
    @MainActor
    final class Gate {
        private var open = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        func wait() async {
            if open { return }
            await withCheckedContinuation { waiters.append($0) }
        }
        func release() {
            open = true
            waiters.forEach { $0.resume() }
            waiters = []
        }
    }

    /// A 96×96 transparent canvas with a centred opaque disc, like a static PokéAPI sprite.
    private func discImage() throws -> NSBitmapImageRep {
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 96, pixelsHigh: 96, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.systemRed.setFill()
        NSBezierPath(ovalIn: NSRect(x: 16, y: 16, width: 64, height: 64)).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// The disc as a one-frame GIF, so the animated sprite path finds it in the store too.
    private func gif(_ rep: NSBitmapImageRep) throws -> Data {
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "com.compuserve.gif" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(rep.cgImage),
                                   [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    /// A hatched 1 that has played its hatch already (or still an egg with `hatched: false`), with the pet
    /// shown and live. `sleep` drives the player; the default never returns, so sequences end only when a
    /// test says so. The egg sprite itself comes from the shared sprite cache.
    private func makeFixture(
        hatched: Bool = true,
        sleep: @escaping @MainActor (TimeInterval) async throws -> Void = { _ in try await Task.sleep(for: .seconds(3600)) },
        sessionRecheckWait: @escaping @MainActor () async throws -> Void = { try await Task.sleep(for: .milliseconds(20)) },
        clock: (@MainActor () -> Date)? = nil
    ) async throws -> Fixture {
        let suite = "FloatingPetCelebrationTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let disc = try discImage()
        let png = try XCTUnwrap(disc.representation(using: .png, properties: [:])), animated = try gif(disc)
        for id in [1, 2, 3] {
            for shiny in [false, true] {
                try png.write(to: directory.appendingPathComponent(
                    SpriteStore.cacheKey(speciesID: id, animated: false, shiny: shiny) + ".png"))
                try animated.write(to: directory.appendingPathComponent(
                    SpriteStore.cacheKey(speciesID: id, animated: true, shiny: shiny) + ".gif"))
            }
        }
        let file = directory.appendingPathComponent("companion.json")
        let store = UsageStore(providers: [], autoRefresh: false, defaults: defaults)
        let companion = CompanionStore(provider: StubProvider(value: Self.line), fileURL: file,
                                       rng: SeededRNG(seed: 7), defaults: defaults)
        if hatched {
            await companion.hatch(baseID: 1)
            companion.celebrations.items.forEach { companion.finishCelebration(id: $0.id) }
        }
        let player = clock.map { CelebrationPlayer(clock: $0, sleep: sleep) } ?? CelebrationPlayer(sleep: sleep)
        let session = SessionBox()
        var opened = 0
        let controller = FloatingPetController(store: store, companion: companion, defaults: defaults,
                                               onOpenPopover: { opened += 1 }, motionOverride: true,
                                               celebrationPlayer: player, spriteStore: SpriteStore(directory: directory),
                                               sessionProbe: { session.state }, sessionRecheckWait: sessionRecheckWait)
        let fixture = Fixture(controller: controller, store: store, companion: companion, defaults: defaults,
                              player: player, session: session,
                              opened: { opened }, cleanUp: {
            controller.setDisplayAwake(false)   // hides the panel
            store.floatingPetEnabled = false
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        })
        store.floatingPetEnabled = true
        await waitUntil { companion.floatingPetLive }
        XCTAssertTrue(companion.floatingPetLive, "the shown pet is live")
        return fixture
    }

    /// Evolves 1 → 2 and waits for the pet to start the sequence.
    @discardableResult
    private func evolve(_ fixture: Fixture) async throws -> Int {
        fixture.companion.applyUsage(fixture.companion.threshold)
        let item = try XCTUnwrap(fixture.companion.celebrations.items.first, "evolve queued")
        XCTAssertNotNil(item.deferred, "the live pet holds the notification")
        await waitUntil { fixture.player.item?.id == item.id }
        XCTAssertEqual(fixture.player.item?.id, item.id, "the pet plays it")
        return item.id
    }

    /// Settings observation hops through a Task; give it a bounded chance to run.
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func testHideDuringPlaybackLeavesItemUnseen() async throws {
        for hide in ["disable", "sleep"] {
            let fixture = try await makeFixture()
            defer { fixture.cleanUp() }
            let id = try await evolve(fixture)
            if hide == "disable" {
                fixture.store.floatingPetEnabled = false
                await waitUntil { !fixture.companion.floatingPetLive }
            } else {
                fixture.controller.setDisplayAwake(false)
            }
            XCTAssertNil(fixture.player.item, "\(hide): the sequence stops with the pet")
            XCTAssertEqual(fixture.companion.celebrations.items.map(\.id), [id], "\(hide): unseen, still queued")
            XCTAssertFalse(fixture.companion.floatingPetLive, hide)
            XCTAssertNil(fixture.companion.celebrations.items.first?.deferred,
                         "\(hide): nobody is live, so the held notification went out")
        }
    }

    /// U1: the popover opening mid-sequence does not take the item away from the pet: both play it from the
    /// same start. Closing the popover again changes nothing on the pet (no restart from 0).
    func testPopoverOpeningAndClosingMidSequenceKeepsThePetPlaying() async throws {
        let fixture = try await makeFixture()
        defer { fixture.cleanUp() }
        let id = try await evolve(fixture)
        let start = try XCTUnwrap(fixture.player.startedAt)
        fixture.companion.popoverOpen = true
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(fixture.player.item?.id, id, "still playing on the pet")
        XCTAssertEqual(fixture.player.startedAt, start)
        XCTAssertEqual(fixture.companion.celebrationPlayback?.startedAt, start, "the popover joins at this start")
        XCTAssertNotNil(fixture.companion.celebrations.items.first?.deferred, "one live surface still holds it")
        fixture.companion.popoverOpen = false
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(fixture.player.item?.id, id)
        XCTAssertEqual(fixture.player.startedAt, start, "the pet keeps playing: it never restarts from 0")
    }

    /// No spoiler on the pet: until its own reveal (or the item is seen), it shows the source.
    func testPendingItemShowsItsSourceUntilFinished() async throws {
        let fixture = try await makeFixture()
        defer { fixture.cleanUp() }
        let id = try await evolve(fixture)
        fixture.companion.popoverOpen = true
        XCTAssertEqual(fixture.companion.representativeSubject.speciesID, 2, "the store has already evolved")
        XCTAssertEqual(fixture.controller.displayedSubject.speciesID, 1, "the pet has not")
        fixture.companion.finishCelebration(id: id)   // the popover played it to the end first
        await waitUntil { fixture.player.item == nil }
        XCTAssertNil(fixture.player.item, "seen elsewhere: the pet stops")
        XCTAssertEqual(fixture.controller.displayedSubject.speciesID, 2, "revealed once seen")
    }

    /// The pet can stop being live inside its player's run, before the reveal: the end that follows is not a
    /// finish. R1: that run leaves no shared start behind, so the next playback starts fresh from 0 instead of
    /// joining a start that is already over (which finished the item at once, unseen).
    func testFinishAfterThePetStoppedBeingLiveDoesNotMarkItSeen() async throws {
        let gate = Gate()
        final class Calls { var count = 0 }
        let calls = Calls()
        var onWake: (@MainActor () -> Void)?
        let fixture = try await makeFixture(sleep: { _ in
            calls.count += 1
            if calls.count > 3 { try await Task.sleep(for: .seconds(3600)) }   // the replay stays on screen
            await gate.wait()
            onWake?()
        })
        defer { fixture.cleanUp() }
        let id = try await evolve(fixture)
        let firstStart = try XCTUnwrap(fixture.player.startedAt)
        let before = fixture.companion.latestEvent
        var playbackAfterDrop: CompanionStore.CelebrationPlayback?
        // The pet stops being live inside the player's first sleep (before the reveal): the rest of the run
        // and its end happen before the pet's sync can stop it.
        onWake = {
            fixture.companion.floatingPetLive = false
            playbackAfterDrop = fixture.companion.celebrationPlayback
            onWake = nil
        }
        gate.release()
        await waitUntil { calls.count > 3 }
        XCTAssertNil(playbackAfterDrop, "no longer live: its registration ends with it")
        XCTAssertEqual(fixture.companion.celebrations.items.map(\.id), [id], "not seen: it replays")
        XCTAssertNotEqual(fixture.companion.latestEvent, before, "nobody live: the held notification went out")
        // Live again (the pet is still shown): the replay starts from 0, on screen.
        XCTAssertEqual(fixture.player.item?.id, id)
        let replay = try XCTUnwrap(fixture.player.startedAt)
        XCTAssertGreaterThan(replay, firstStart, "a fresh start, not the old one")
        XCTAssertLessThan(fixture.player.elapsed(at: Date()), 1, "plays visibly from 0")
        XCTAssertEqual(fixture.companion.celebrationPlayback?.startedAt, replay)
    }

    /// Lock screen and switched-out user: the window stays "visible", but nobody sees the pet. Read from the
    /// session (`CGSessionCopyCurrentDictionary`); the "un-" notification triggers the re-check.
    func testLockedSessionStopsThePlaybackAndRecoversOnTheUnNotice() async throws {
        let cases: [(String, C.SessionState, C.SessionNotice, C.SessionNotice)] = [
            ("lock", .init(screenLocked: true), .locked, .unlocked),
            ("user switch", .init(onConsole: false), .resignedActive, .becameActive),
        ]
        for (name, interrupted, start, end) in cases {
            let fixture = try await makeFixture()
            defer { fixture.cleanUp() }
            let id = try await evolve(fixture)
            fixture.session.state = interrupted
            fixture.controller.sessionDidChange(start)
            XCTAssertNil(fixture.player.item, "\(name): stopped like the hide path")
            XCTAssertFalse(fixture.companion.floatingPetLive, name)
            XCTAssertFalse(fixture.controller.sessionInteractive, name)
            XCTAssertEqual(fixture.companion.celebrations.items.map(\.id), [id], "\(name): unseen, still queued")

            fixture.session.state = .init()
            fixture.controller.sessionDidChange(end)
            XCTAssertTrue(fixture.companion.floatingPetLive, "\(name): live again")
            await waitUntil { fixture.player.item != nil }
            XCTAssertEqual(fixture.player.item?.id, id, "\(name): replayed")
        }
        // A start notification counts even while the system state still reads interactive.
        let fixture = try await makeFixture()
        defer { fixture.cleanUp() }
        try await evolve(fixture)
        fixture.controller.sessionDidChange(.locked)
        XCTAssertNil(fixture.player.item)
    }

    /// The screensaver is a flag driven by its own start/stop notifications (no process scan): its engine is
    /// still running when `didstop` arrives, and nothing would look again while the pet stays hidden.
    func testScreensaverFlagFollowsItsNotifications() async throws {
        let fixture = try await makeFixture()
        defer { fixture.cleanUp() }
        let id = try await evolve(fixture)
        fixture.controller.sessionDidChange(.screensaverStarted)
        XCTAssertNil(fixture.player.item)
        XCTAssertFalse(fixture.companion.floatingPetLive)
        fixture.controller.setDisplayAwake(true)   // any later re-check: still behind the screensaver
        XCTAssertFalse(fixture.companion.floatingPetLive, "the flag holds until didstop, unlike a one-shot notice")

        fixture.controller.sessionDidChange(.screensaverStopped)
        XCTAssertTrue(fixture.companion.floatingPetLive, "didstop alone brings the pet back")
        await waitUntil { fixture.player.item != nil }
        XCTAssertEqual(fixture.player.item?.id, id)
    }

    /// The session dictionary can lag behind the "un-" notification. One one-shot re-check a moment later reads
    /// it again, so a stale read heals itself; it is a single task that ends, never a repeating timer.
    func testUnNoticeRechecksOnceForAStaleSessionRead() async throws {
        let gate = Gate()
        let fixture = try await makeFixture(sessionRecheckWait: { await gate.wait() })
        defer { fixture.cleanUp() }
        let id = try await evolve(fixture)
        fixture.session.state = .init(screenLocked: true)
        fixture.controller.sessionDidChange(.locked)
        XCTAssertFalse(fixture.companion.floatingPetLive)
        XCTAssertFalse(fixture.controller.sessionRecheckPending, "no re-check for a start notice")

        fixture.controller.sessionDidChange(.unlocked)   // arrives while the session still reads locked
        XCTAssertFalse(fixture.companion.floatingPetLive, "stale read: still locked")
        XCTAssertTrue(fixture.controller.sessionRecheckPending)
        // Let every observation-triggered sync run out first: from here, only the re-check looks again.
        try await Task.sleep(for: .milliseconds(150))
        fixture.session.state = .init()   // the session catches up; no further notification comes
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(fixture.companion.floatingPetLive, "nothing else re-reads the session while hidden")
        gate.release()   // the re-check's ~1 s wait is over
        await waitUntil { fixture.companion.floatingPetLive }
        XCTAssertTrue(fixture.companion.floatingPetLive, "the one-shot re-check recovered")
        XCTAssertFalse(fixture.controller.sessionRecheckPending, "the re-check ended: nothing left running")
        await waitUntil { fixture.player.item != nil }
        XCTAssertEqual(fixture.player.item?.id, id)
    }

    /// The popover reads the same session state (`sessionInteractive`) through this callback.
    func testSessionChangesAreReportedOnce() async throws {
        let fixture = try await makeFixture()
        defer { fixture.cleanUp() }
        var reported: [Bool] = []
        fixture.controller.onSessionInteractiveChange = { reported.append($0) }
        fixture.session.state = .init(screenLocked: true)
        fixture.controller.sessionDidChange(.locked)
        fixture.controller.setDisplayAwake(true)   // another sync with the same session state
        fixture.session.state = .init()
        fixture.controller.sessionDidChange(.unlocked)
        XCTAssertEqual(reported, [false, true])
    }

    /// U1: with the popover open the pet still plays the item, holding its notification for the first end.
    func testPetPlaysAlongsideTheOpenPopover() async throws {
        let fixture = try await makeFixture()
        defer { fixture.cleanUp() }
        fixture.companion.popoverOpen = true
        fixture.companion.applyUsage(fixture.companion.threshold)
        let id = try XCTUnwrap(fixture.companion.celebrations.items.first?.id)
        XCTAssertNotNil(fixture.companion.celebrations.items.first?.deferred)
        await waitUntil { fixture.player.item?.id == id }
        XCTAssertEqual(fixture.player.item?.id, id, "the pet plays it too")
        XCTAssertEqual(fixture.controller.displayedSubject.speciesID, 1, "no spoiler before its reveal")
    }

    /// U1: a popover opened mid-sequence joins the pet in phase (same start), a skip on either surface moves
    /// both, and when the pet reaches the end first the popover's player stops without finishing twice.
    func testPopoverJoinsThePetInPhaseAndFollowsItsEnd() async throws {
        for skipper in ["pet", "popover"] {
            let fixture = try await makeFixture()
            defer { fixture.cleanUp() }
            let id = try await evolve(fixture)
            let petStart = try XCTUnwrap(fixture.player.startedAt)
            fixture.companion.popoverOpen = true
            let popoverPlayer = CelebrationPlayer(sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
            defer { popoverPlayer.cancel() }
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("u1-\(UUID())")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            // Low Power came on after the pet started: the popover still joins the pet's full version (R2).
            let host = NSHostingView(rootView: CompanionHeader(store: fixture.companion,
                                                               spriteStore: SpriteStore(directory: directory),
                                                               celebrationPlayer: popoverPlayer,
                                                               motion: { MotionSettings(lowPower: true) })
                .celebrationStageHost().frame(width: 332, height: 170))
            host.frame = NSRect(x: 0, y: 0, width: 332, height: 170)
            let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 332, height: 170),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.orderFront(nil)
            defer { window.close() }
            await waitUntil { popoverPlayer.item?.id == id }
            XCTAssertEqual(popoverPlayer.item?.id, id, skipper)
            XCTAssertEqual(popoverPlayer.startedAt, petStart, "\(skipper): joined at the pet's start, same phase")
            XCTAssertEqual(popoverPlayer.timeline?.reduced, false, "\(skipper): and on the pet's timeline (R2)")

            if skipper == "pet" {
                fixture.controller.petClicked()
                let skipped = try XCTUnwrap(fixture.player.startedAt)
                XCTAssertNotEqual(skipped, petStart)
                await waitUntil { popoverPlayer.startedAt == skipped }
                XCTAssertEqual(popoverPlayer.startedAt, skipped, "the popover follows the pet's skip")
            } else {
                popoverPlayer.skip()   // a click on the popover's stage
                let skipped = try XCTUnwrap(popoverPlayer.startedAt)
                XCTAssertNotEqual(skipped, petStart)
                await waitUntil { fixture.player.startedAt == skipped }
                XCTAssertEqual(fixture.player.startedAt, skipped, "the pet follows the popover's skip")
            }

            let before = fixture.companion.latestEvent
            fixture.companion.finishCelebration(id: id)   // the pet reached the end first
            await waitUntil { popoverPlayer.item == nil }
            XCTAssertNil(popoverPlayer.item, "\(skipper): the popover stops, the item was seen")
            XCTAssertNotEqual(fixture.companion.latestEvent, before)
            XCTAssertNil(fixture.companion.celebrationPlayback)
        }
    }

    /// U2 (the reported path): popover open and pet live, an evolution, the popover plays it to the end first.
    /// The item is seen once; the pet stops, and closing the popover never replays it on the pet.
    func testPopoverPlayedToTheEndIsNeverReplayedOnThePet() async throws {
        let fixture = try await makeFixture()   // the pet's own sleeps never return: the popover ends first
        defer { fixture.cleanUp() }
        var texts: [String] = []
        fixture.companion.companionEventObserver = { texts.append($0.text) }
        fixture.companion.popoverOpen = true
        // The popover's header with its own player: the wall clock plus whatever its sleeps "waited".
        final class Offset { var seconds: TimeInterval = 0 }
        let offset = Offset()
        let popoverPlayer = CelebrationPlayer(clock: { Date().addingTimeInterval(offset.seconds) },
                                              sleep: { offset.seconds += $0 })
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("u2-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let host = NSHostingView(rootView: CompanionHeader(store: fixture.companion,
                                                           spriteStore: SpriteStore(directory: directory),
                                                           celebrationPlayer: popoverPlayer)
            .celebrationStageHost().frame(width: 332, height: 170))
        host.frame = NSRect(x: 0, y: 0, width: 332, height: 170)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 332, height: 170),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }

        fixture.companion.applyUsage(fixture.companion.threshold)   // Lixy evolves, popover open, pet shown
        let id = try XCTUnwrap(fixture.companion.celebrations.items.first?.id)
        await waitUntil { fixture.companion.celebrations.items.isEmpty }
        XCTAssertTrue(fixture.companion.celebrations.items.isEmpty, "the popover played it to the end: seen")
        await waitUntil { fixture.player.item == nil }
        XCTAssertNil(fixture.player.item, "the pet, which played it in sync, stops")
        XCTAssertEqual(texts, [fixture.companion.l.notifEvolveBody(from: "P1", to: "P2")], "announced once")

        fixture.companion.popoverOpen = false   // the user closes the popover
        window.contentView = nil
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertNil(fixture.player.item, "never replayed on the pet")
        XCTAssertFalse(fixture.companion.celebrations.items.contains { $0.id == id })
        XCTAssertEqual(texts.count, 1, "no second notification")
    }

    func testPlaybackGrowsThePanelAroundTheGroundedPet() async throws {
        let fixture = try await makeFixture()
        defer { fixture.cleanUp() }
        let pet = CGFloat(fixture.store.floatingPetSize)
        let rest = try XCTUnwrap(fixture.controller.panelFrame)
        let restPet = C.petOrigin(panelOrigin: rest.origin, petSize: pet, panelSize: rest.size)
        let id = try await evolve(fixture)
        await waitUntil { fixture.controller.panelFrame?.size != rest.size }
        let playing = try XCTUnwrap(fixture.controller.panelFrame)
        XCTAssertEqual(playing.size, C.panelSize(petSize: pet, showingBubble: true, celebrating: true),
                       "room for the effects and the announce line")
        XCTAssertEqual(C.petOrigin(panelOrigin: playing.origin, petSize: pet, panelSize: playing.size,
                                   celebrating: true), restPet,
                       "the pet does not move when the sequence starts")
        XCTAssertEqual(playing.minY, rest.minY - CelebrationStage.effectsMargin, "room below the feet")

        // Seen elsewhere (or the queue was reset): the pet stops and shrinks back.
        fixture.companion.finishCelebration(id: id)
        await waitUntil { fixture.controller.panelFrame?.size == rest.size }
        XCTAssertNil(fixture.player.item)
        let after = try XCTUnwrap(fixture.controller.panelFrame)
        XCTAssertEqual(after.size, rest.size, "back to the resting panel")
        XCTAssertEqual(C.petOrigin(panelOrigin: after.origin, petSize: pet, panelSize: after.size), restPet)
    }

    /// A drag during a sequence saves the pet's spot, not the grown panel's corner. A large pet: from
    /// 125 pt the effects margin, not the bubble column, sets the panel width.
    func testDragWhilePlayingPersistsThePetOrigin() async throws {
        let fixture = try await makeFixture()
        defer { fixture.cleanUp() }
        fixture.store.floatingPetSize = 192
        try await evolve(fixture)
        let pet = CGFloat(fixture.store.floatingPetSize)
        await waitUntil { fixture.controller.panelFrame?.width == pet + 2 * CelebrationStage.effectsMargin }
        let size = try XCTUnwrap(fixture.controller.panelFrame?.size)
        let dropped = NSPoint(x: 500, y: 300)
        fixture.controller.panelDidMove(panelOrigin: dropped, panelSize: size, userDragging: true)
        let expected = C.petOrigin(panelOrigin: dropped, petSize: pet, panelSize: size, celebrating: true)
        XCTAssertEqual(expected, NSPoint(x: 528, y: 328), "inset by the margin on the side and below")
        XCTAssertEqual(fixture.defaults.double(forKey: "floatingPetOriginX"), Double(expected.x))
        XCTAssertEqual(fixture.defaults.double(forKey: "floatingPetOriginY"), Double(expected.y))
    }

    /// An agent's "done" run during a sequence takes the stage's room along to the cursor.
    func testRunToCursorKeepsTheStageRoom() async throws {
        let fixture = try await makeFixture()
        defer { fixture.cleanUp() }
        fixture.store.floatingPetSize = 192
        try await evolve(fixture)
        let frame = fixture.controller.beginRun(cursor: NSPoint(x: 800, y: 600),
                                                visibleFrame: NSRect(x: 0, y: 0, width: 1440, height: 900))
        XCTAssertEqual(frame.size, C.panelSize(petSize: 192, showingBubble: true, celebrating: true))
    }

    /// During a hatch the pet shows the egg, whose click would pray; while it plays, a click only skips.
    func testClickWhilePlayingSkipsOnly() async throws {
        let fixture = try await makeFixture(hatched: false)
        defer { fixture.cleanUp() }
        await fixture.companion.hatch(baseID: 1)
        let id = try XCTUnwrap(fixture.companion.celebrations.items.first?.id)
        await waitUntil { fixture.player.item?.id == id }
        XCTAssertNil(fixture.controller.displayedSubject.speciesID, "the egg is on stage")
        let wobbles = fixture.controller.prayerBurst.wobbleCount
        fixture.controller.petClicked()
        let timeline = try XCTUnwrap(fixture.player.timeline)
        XCTAssertGreaterThanOrEqual(fixture.player.elapsed(at: Date()), timeline.skipTarget, "skipped to the reveal")
        XCTAssertEqual(fixture.opened(), 0, "no popover")
        XCTAssertEqual(fixture.controller.prayerBurst.wobbleCount, wobbles, "no prayer")
        XCTAssertTrue(fixture.controller.prayerBurst.particles.isEmpty, "no 🙏")

        fixture.companion.finishCelebration(id: id)   // played to the end (here, or on the popover)
        await waitUntil { fixture.player.item == nil }
        fixture.controller.petClicked()
        XCTAssertEqual(fixture.opened(), 1, "at rest a hatched pet opens the popover again")
    }

    /// The player's own end (every sleep returns at once here) finishes the item through the store.
    func testFinishedSequenceReleasesItsNotification() async throws {
        let fixture = try await makeFixture(sleep: { _ in })
        defer { fixture.cleanUp() }
        let before = fixture.companion.latestEvent
        fixture.companion.applyUsage(fixture.companion.threshold)
        XCTAssertNotNil(fixture.companion.celebrations.items.first?.deferred)
        await waitUntil { fixture.companion.celebrations.items.isEmpty }
        XCTAssertTrue(fixture.companion.celebrations.items.isEmpty, "seen: played to the end on the pet")
        XCTAssertNotEqual(fixture.companion.latestEvent, before, "announced after playback")
        XCTAssertNil(fixture.player.item)
    }

    // MARK: Pass 2 (seen at the reveal, shared playback)

    /// The popover's header on `companion`, in an offscreen window (closed by the caller).
    private func mountHeader(_ companion: CompanionStore, player: CelebrationPlayer,
                             motion: @escaping @MainActor () -> MotionSettings = { MotionSettings() }) throws -> NSWindow {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("pass2-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let host = NSHostingView(rootView: CompanionHeader(store: companion, spriteStore: SpriteStore(directory: directory),
                                                           celebrationPlayer: player, motion: motion)
            .celebrationStageHost().frame(width: 332, height: 170))
        host.frame = NSRect(x: 0, y: 0, width: 332, height: 170)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 332, height: 170),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        return window
    }

    /// R3, the reported Lixy path: pet live, popover open, the item plays on both. The popover is past
    /// `evolveDone` and is closed during the caption hold (8–12 s). The pet goes on from the same start (no
    /// restart), the item finishes once, one notification. Under the old single-owner rule the pet was stopped
    /// while the popover played and restarted from 0 on close.
    func testClosingThePopoverDuringTheCaptionHoldKeepsThePetPlaying() async throws {
        final class Clock { var now = Date(timeIntervalSince1970: 50_000) }
        let clock = Clock()
        let petGate = Gate()
        let fixture = try await makeFixture(sleep: { _ in await petGate.wait() }, clock: { clock.now })
        defer { fixture.cleanUp() }
        var texts: [String] = []
        fixture.companion.companionEventObserver = { texts.append($0.text) }
        fixture.companion.popoverOpen = true
        fixture.companion.applyUsage(fixture.companion.threshold)   // Lixy evolves: the pet starts it
        let id = try XCTUnwrap(fixture.companion.celebrations.items.first?.id)
        await waitUntil { fixture.player.item?.id == id }
        let start = try XCTUnwrap(fixture.player.startedAt)

        clock.now = start.addingTimeInterval(9)   // the popover shows up 9 s in: past the reveal
        let popoverPlayer = CelebrationPlayer(clock: { clock.now }, sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
        defer { popoverPlayer.cancel() }
        let window = try mountHeader(fixture.companion, player: popoverPlayer)
        defer { window.close() }
        await waitUntil { popoverPlayer.text == .evolveDone }
        XCTAssertEqual(popoverPlayer.startedAt, start, "both play it from one start")
        XCTAssertEqual(popoverPlayer.text, .evolveDone, "the popover is in the caption hold")

        fixture.companion.popoverOpen = false   // closed during the caption hold
        window.contentView = nil
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(fixture.player.item?.id, id, "the pet keeps playing")
        XCTAssertEqual(fixture.player.startedAt, start, "from the same start: no restart from 0")
        XCTAssertEqual(texts, [], "the pet still holds the caption: not finished yet")

        petGate.release()   // the pet reaches its end
        await waitUntil { fixture.companion.celebrations.items.isEmpty }
        await waitUntil { fixture.player.item == nil }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNil(fixture.player.item, "finished once, never replayed")
        XCTAssertEqual(texts, [fixture.companion.l.notifEvolveBody(from: "P1", to: "P2")], "one notification")
    }

    /// R6 on the pet alone: hidden after the reveal, the item counts as seen (once); before it, unseen.
    func testHidingThePetAfterTheRevealFinishesTheItem() async throws {
        for (name, sleepsBeforeParking, seen) in [("after the reveal", 2, true), ("before the reveal", 0, false)] {
            final class Calls { var count = 0 }
            let calls = Calls()
            let fixture = try await makeFixture(sleep: { _ in
                calls.count += 1
                if calls.count > sleepsBeforeParking { try await Task.sleep(for: .seconds(3600)) }
            })
            defer { fixture.cleanUp() }
            var texts: [String] = []
            fixture.companion.companionEventObserver = { texts.append($0.text) }
            fixture.companion.applyUsage(fixture.companion.threshold)
            let id = try XCTUnwrap(fixture.companion.celebrations.items.first?.id)
            await waitUntil { fixture.player.item?.id == id && calls.count > sleepsBeforeParking }
            XCTAssertEqual(fixture.player.text == .evolveDone, seen, "\(name): where the pet stands")
            fixture.store.floatingPetEnabled = false   // Hide
            await waitUntil { !fixture.companion.floatingPetLive }
            XCTAssertEqual(fixture.companion.celebrations.items.isEmpty, seen, "\(name): seen = reveal reached")
            XCTAssertEqual(texts.count, 1, "\(name): one notification either way (seen, or nobody live)")
            XCTAssertNil(fixture.companion.celebrationPlayback, name)
        }
    }
}
