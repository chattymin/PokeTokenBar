import XCTest
@testable import PokeTokenBar

private enum UnownTestError: Error { case offline }

/// 부화 라인은 메모리에서 반환하고, 새 알 프리패치는 실패시켜 네트워크를 사용하지 않는다.
private struct UnownTestProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: baseSpeciesID, tree: EvoNode(speciesID: baseSpeciesID, children: []),
                rarity: .common,
                names: [baseSpeciesID: ["ko": "안농", "en": "Unown", "ja": "アンノーン"]])
    }

    func baseSpeciesIndex() async throws -> [BaseSpecies] { throw UnownTestError.offline }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { throw UnownTestError.offline }
}

private struct UnownSelectionProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        try await UnownTestProvider().line(baseSpeciesID: baseSpeciesID)
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] {
        [BaseSpecies(id: 25, captureRate: 255), BaseSpecies(id: 201, captureRate: 225)]
    }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { throw UnownTestError.offline }
}

private actor UnownPrefetchSignal {
    private var fired = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func fire() {
        fired = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }

    func wait() async {
        if fired { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

private struct UnownPrefetchProvider: PokeProviding {
    let lineRequested: UnownPrefetchSignal

    func line(baseSpeciesID: Int) async throws -> EvoLine {
        await lineRequested.fire()
        return try await UnownTestProvider().line(baseSpeciesID: baseSpeciesID)
    }

    func baseSpeciesIndex() async throws -> [BaseSpecies] { [BaseSpecies(id: 201, captureRate: 255)] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { BaseSpecies(id: 201, captureRate: 255) }
}

private actor UnownRetryProvider: PokeProviding {
    private var lineAttempts = 0

    func line(baseSpeciesID: Int) async throws -> EvoLine {
        lineAttempts += 1
        if lineAttempts == 1 { throw UnownTestError.offline }
        return try await UnownTestProvider().line(baseSpeciesID: baseSpeciesID)
    }

    func baseSpeciesIndex() async throws -> [BaseSpecies] { throw UnownTestError.offline }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { throw UnownTestError.offline }
}

@MainActor
final class UnownTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func mon(_ form: PokemonForm?, shiny: Bool = false, speciesID: Int = 201) -> MonState {
        MonState(baseID: speciesID, pathIDs: [speciesID], stageIndex: 0, usedAtStage: 123,
                 rarity: .common, totalForms: 1, isShiny: shiny, nature: .brave, form: form)
    }

    private func entry(_ form: PokemonForm?, shiny: Bool = false, speciesID: Int = 201) -> DexEntry {
        DexEntry(baseID: speciesID, finalID: speciesID, chainOrder: [speciesID], rarity: .common,
                 caughtAt: now, isShiny: shiny, nature: .brave,
                 names: [speciesID: ["ko": "안농", "en": "Unown"]], form: form)
    }

    private func stateURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("unown-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("companion-state.json")
    }

    private func store(_ state: CompanionState = CompanionState(), seed: UInt64 = 7,
                       at url: URL? = nil,
                       provider: any PokeProviding = UnownTestProvider()) throws -> CompanionStore {
        let destination = try url ?? stateURL()
        try JSONEncoder().encode(state).write(to: destination)
        return reload(at: destination, seed: seed, provider: provider)
    }

    private func reload(at url: URL, seed: UInt64 = 7,
                        provider: any PokeProviding = UnownTestProvider()) -> CompanionStore {
        let date = now
        let suite = "unown-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(1.0, forKey: "growthDifficulty")
        defaults.set(1.0, forKey: "shopDifficulty")
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        return CompanionStore(provider: provider, clock: { date },
                              fileURL: url, rng: SeededRNG(seed: seed),
                              dittoDisguiseRollingEnabled: false, defaults: defaults)
    }

    func testAllLettersAndPunctuationAreSelectable() {
        let symbols = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init) + ["!", "?"]
        XCTAssertEqual(PokemonForm.unownLetters.map(\.symbol), symbols)
        XCTAssertEqual((0..<56).map { PokemonForm.roll(UInt64($0), among: PokemonForm.unownLetters, collected: []).symbol },
                       symbols.flatMap { [$0, $0] })
        XCTAssertEqual(PokemonForm.roll(56, among: PokemonForm.unownLetters, collected: []), .a)
        XCTAssertTrue(PokemonForm.unownLetters.contains(PokemonForm.roll(UInt64.max, among: PokemonForm.unownLetters, collected: [])))
    }

    func testFormWeightsAreTwoForMissingAndOneForCollectedWithoutGuaranteeingNewForms() {
        for collected in [Set<PokemonForm>(), [.a, .b, .exclamation], Set(PokemonForm.unownLetters)] {
            let total = 56 - collected.count
            let samples = (0..<total).map { PokemonForm.roll(UInt64($0), among: PokemonForm.unownLetters, collected: collected) }
            for form in PokemonForm.unownLetters {
                XCTAssertEqual(samples.filter { $0 == form }.count, collected.contains(form) ? 1 : 2)
            }
            XCTAssertEqual(PokemonForm.roll(UInt64(total), among: PokemonForm.unownLetters, collected: collected), .a)
        }
        XCTAssertEqual((0..<28).map { PokemonForm.roll(UInt64($0), among: PokemonForm.unownLetters, collected: Set(PokemonForm.unownLetters)) },
                       PokemonForm.unownLetters, "Completion returns selection to uniform weights")
    }

    func testSharedCollectedAdjustmentPreservesCaptureRateRoundingAndMinimum() {
        for weight in 0...255 {
            XCTAssertEqual(CollectionWeight.adjusted(weight, isCollected: false), max(1, weight))
            XCTAssertEqual(CollectionWeight.adjusted(weight, isCollected: true), max(1, weight / 2))
        }
    }

    func testCollectionIncludesLegacyActiveAndReleasedFormsButCountsShinyOnlyOnce() throws {
        var original = CompanionState()
        var legacy = entry(nil)
        legacy.form = nil
        var released = entry(.exclamation, shiny: true)
        released.releasedAt = now
        original.dex = [legacy, entry(.b), entry(.b, shiny: true), released, entry(nil, speciesID: 25)]
        original.active = mon(.question, shiny: true)
        XCTAssertEqual(original.collectedForms(speciesID: PokemonForm.unownSpeciesID), [.a, .b, .exclamation, .question])
        let s = try store(original)
        XCTAssertEqual(s.dexSpecies.map(\.id), [25, 201])
        XCTAssertEqual(s.formSpecies(speciesID: PokemonForm.unownSpeciesID).compactMap(\.form), [.a, .b, .exclamation, .question])
        XCTAssertEqual(s.formSpecies(speciesID: PokemonForm.unownSpeciesID).map(\.isShiny), [false, true, true, true])
        XCTAssertEqual(s.formSpecies(speciesID: PokemonForm.unownSpeciesID).map(\.isRaising), [false, false, false, true])
    }

    func testMissingADoesNotCreateAnOwnedFormOrPermitAnUncollectedRepresentative() throws {
        var original = CompanionState()
        original.dex = [entry(.question, shiny: true)]
        let s = try store(original)
        XCTAssertEqual(s.dexSpecies.map(\.id), [201])
        XCTAssertEqual(s.formSpecies(speciesID: PokemonForm.unownSpeciesID).compactMap(\.form), [.question])
        XCTAssertFalse(s.setRepresentativeSpeciesID(201, form: .a))
        XCTAssertTrue(s.setRepresentativeSpeciesID(201, form: .question))
        XCTAssertTrue(s.isRepresentative(try XCTUnwrap(s.dexSpecies.first)))
    }

    func testHatchUsesOwnedFormWeightsAfterUnchangedShinyNatureAndProfileRolls() async throws {
        var original = CompanionState()
        original.dex = PokemonForm.unownLetters.dropLast().map { entry($0) }
        let seed = try XCTUnwrap((UInt64(0)..<1_000).first { seed in
            var rng = SeededRNG(seed: seed)
            _ = rng.next(); _ = rng.next(); _ = rng.next()
            let roll = rng.next()
            return roll % 29 == 27 && roll % 56 / 2 != 27
        })
        let s = try store(original, seed: seed)
        await s.hatch(baseID: 201)
        XCTAssertEqual(s.currentForm, .question, "The missing form occupies both final slots of the weighted pool")
    }

    func testPrefetchUsesOwnedFormWeights() async throws {
        var original = CompanionState()
        original.installBaselineSet = true
        original.lastDate = "d1"
        original.dex = PokemonForm.unownLetters.dropLast().map { entry($0) }
        let seed = try XCTUnwrap((UInt64(0)..<1_000).first { seed in
            var rng = SeededRNG(seed: seed)
            _ = rng.next() // Species selection precedes form selection.
            let roll = rng.next()
            return roll % 29 == 27 && roll % 56 / 2 != 27
        })
        let signal = UnownPrefetchSignal()
        let s = try store(original, seed: seed, provider: UnownPrefetchProvider(lineRequested: signal))
        s.update(todayTokensByProvider: ["test": 1_000], todayDate: "d1", monthTotal: 0,
                 burnTier: .idle, limitWarning: false, hasUsageData: true)
        await signal.wait()
        XCTAssertEqual(s.state.pendingHatchID, 201)
        XCTAssertEqual(s.state.pendingForm, .question)
    }

    func testFormOwnershipDoesNotChangeSpeciesSelectionOrShinyRolls() async throws {
        var selectedSpecies = Set<Int>()
        for seed: UInt64 in [1, 7, 17, 42, 128, 999] {
            for forms in [[], [PokemonForm.b], PokemonForm.unownLetters] {
                var original = CompanionState()
                original.eggUsage = PokemonBalance.eggHatchThreshold
                original.collectedFinals = ["201:201"]
                original.dex = forms.map { entry($0) }
                let s = try store(original, seed: seed, provider: UnownSelectionProvider())
                var rng = SeededRNG(seed: seed)
                // Existing species weights: Pikachu 255, collected Unown floor(225 / 2) = 112.
                let expectedSpecies = rng.next() % 367 < 255 ? 25 : 201
                let expectedShiny = rng.next() % PokemonOdds.shinyDenominator == 0
                let expectedNature = PokemonNature.allCases[Int(rng.next() % UInt64(PokemonNature.allCases.count))]
                let expectedProfileSeed = rng.next()
                await s.hatchIfNeeded()
                XCTAssertEqual(s.currentSpeciesID, expectedSpecies)
                XCTAssertEqual(s.currentIsShiny, expectedShiny)
                XCTAssertEqual(s.currentNature, expectedNature)
                XCTAssertEqual(s.state.active?.profile?.seed, expectedProfileSeed)
                selectedSpecies.insert(try XCTUnwrap(s.currentSpeciesID))
            }
        }
        XCTAssertEqual(selectedSpecies, [25, 201])
    }

    /// 형태 필드 하나가 없거나 잘못돼도 기존 개체·도감·재화가 유실되면 안 된다.
    func testLegacyAndInvalidFormFieldsDefaultToAWithoutLosingProgress() throws {
        let invalidFields: [Any?] = [nil, NSNull(), "future-form", 42]
        for invalid in invalidFields {
            var original = CompanionState()
            original.active = mon(.z, shiny: true)
            original.dex = [entry(.question, shiny: true)]
            original.representativeSpeciesID = 201
            original.representativeForm = .question
            original.usedSinceInstall = 123_456_789
            original.inventory = ["rareCandy": 3]
            let data = try JSONEncoder().encode(original)
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            var active = try XCTUnwrap(json["active"] as? [String: Any])
            var dex = try XCTUnwrap(json["dex"] as? [[String: Any]])
            active["form"] = invalid
            dex[0]["form"] = invalid
            json["active"] = active
            json["dex"] = dex
            json["representativeForm"] = invalid

            let restored = try JSONDecoder().decode(CompanionState.self,
                from: JSONSerialization.data(withJSONObject: json))
            XCTAssertEqual(restored.active?.form, .a)
            XCTAssertEqual(restored.active?.usedAtStage, 123)
            XCTAssertEqual(restored.active?.isShiny, true)
            XCTAssertEqual(restored.dex.count, 1)
            XCTAssertEqual(restored.dex.first?.id, original.dex.first?.id)
            XCTAssertEqual(restored.dex.first?.form, .a)
            XCTAssertEqual(restored.dex.first?.isShiny, true)
            XCTAssertEqual(restored.representativeForm, .a)
            XCTAssertEqual(restored.usedSinceInstall, original.usedSinceInstall)
            XCTAssertEqual(restored.inventory, original.inventory)
        }
    }

    func testAppearanceOwnershipIsIndependentForEachUnownForm() throws {
        var state = CompanionState()
        state.dex = [entry(.a), entry(.a, shiny: true), entry(.b, shiny: true), entry(.c)]
        let s = try store(state)
        XCTAssertEqual(s.formSpecies(speciesID: PokemonForm.unownSpeciesID).map(\.form), [.a, .b, .c])
        XCTAssertEqual(s.formSpecies(speciesID: PokemonForm.unownSpeciesID).map(\.hasNormal), [true, false, true])
        XCTAssertEqual(s.formSpecies(speciesID: PokemonForm.unownSpeciesID).map(\.isShiny), [true, true, false])
        XCTAssertEqual(s.dexSpecies.first?.hasNormal, true)
        XCTAssertEqual(s.dexSpecies.first?.isShiny, true)
    }

    func testEveryFormRoundTripsAndSharesOneSpeciesCell() throws {
        for form in PokemonForm.unownLetters {
            let restored = try JSONDecoder().decode(MonState.self,
                from: JSONEncoder().encode(mon(form, shiny: true)))
            XCTAssertEqual(restored.form, form)
            XCTAssertTrue(restored.isShiny)
        }

        var original = CompanionState()
        original.language = .ko
        original.dex = PokemonForm.unownLetters.map { entry($0, shiny: true) }
        let s = try store(original)
        XCTAssertEqual(s.state.dex.compactMap(\.form), PokemonForm.unownLetters)
        XCTAssertEqual(s.dexSpecies.count, 1)
        XCTAssertEqual(s.dexSpecies.first?.name, "안농")
        XCTAssertEqual(s.dexSpecies.first?.collectionID, "201")
        XCTAssertNil(s.dexSpecies.first?.form)
        XCTAssertEqual(s.state.collectedForms(speciesID: PokemonForm.unownSpeciesID).count, 28)
        XCTAssertEqual(s.formSpecies(speciesID: PokemonForm.unownSpeciesID).compactMap(\.form), PokemonForm.unownLetters)
        XCTAssertEqual(Set(s.formSpecies(speciesID: PokemonForm.unownSpeciesID).map(\.collectionID)).count, 28)
        XCTAssertTrue(s.dexSpecies.allSatisfy { $0.id == 201 && $0.isShiny && !$0.isRaising })
        XCTAssertEqual(s.formSpecies(speciesID: PokemonForm.unownSpeciesID).map(\.name), PokemonForm.unownLetters.map { "안농 [\($0.symbol)]" })
    }

    func testFormIsOnlyAppliedToUnown() throws {
        XCTAssertEqual(mon(nil).form, .a)
        XCTAssertEqual(entry(nil).form, .a)
        let otherMon = mon(.question, speciesID: 25)
        let otherEntry = entry(.question, speciesID: 25)
        XCTAssertNil(otherMon.form)
        XCTAssertNil(otherEntry.form)
        XCTAssertNil(try JSONDecoder().decode(MonState.self,
            from: JSONEncoder().encode(otherMon)).form)
        XCTAssertNil(try JSONDecoder().decode(DexEntry.self,
            from: JSONEncoder().encode(otherEntry)).form)
        XCTAssertEqual(PokemonForm.displayName("Pikachu", speciesID: 25, form: .question, label: nil), "Pikachu")
    }

    func testHatchGraduationAndReloadPreserveLetterAndShiny() async throws {
        for shiny in [false, true] {
            let seed = try XCTUnwrap((UInt64(0)..<20_000).first { seed in
                var rng = SeededRNG(seed: seed)
                let matchesShiny = (rng.next() % PokemonOdds.shinyDenominator == 0) == shiny
                _ = rng.next() // nature
                _ = rng.next() // profile seed
                return matchesShiny && rng.next() % 56 / 2 != 0
            })
            var rng = SeededRNG(seed: seed)
            _ = rng.next()
            let nature = PokemonNature.allCases[Int(rng.next() % UInt64(PokemonNature.allCases.count))]
            let profileSeed = rng.next()
            let form = PokemonForm.unownLetters[Int(rng.next() % 56 / 2)]
            let url = try stateURL()
            let s = try store(seed: seed, at: url)

            await s.hatch(baseID: 201)
            XCTAssertEqual(s.currentForm, form)
            XCTAssertEqual(s.currentIsShiny, shiny)
            XCTAssertEqual(s.currentNature, nature)
            let profile = try XCTUnwrap(s.state.active?.profile)
            XCTAssertEqual(profile.seed, profileSeed)
            XCTAssertTrue(s.setRepresentativeSpeciesID(201, form: form))
            XCTAssertEqual(reload(at: url).state.active?.form, form)

            s.applyUsage(PokemonBalance.graduationTotal(.common))
            XCTAssertNil(s.state.active)
            XCTAssertEqual(s.state.dex.count, 1)
            XCTAssertEqual(s.state.dex.first?.form, form)
            XCTAssertEqual(s.state.dex.first?.isShiny, shiny)
            XCTAssertEqual(s.state.dex.first?.nature, nature)
            XCTAssertEqual(s.state.dex.first?.profile?.instanceID, profile.instanceID)
            XCTAssertEqual(s.state.dex.first?.profile?.ivs, profile.ivs)
            XCTAssertEqual(s.state.dex.first?.profile?.level, 100)
            XCTAssertEqual(s.representativeForm, form)

            let restored = reload(at: url)
            XCTAssertEqual(restored.state.dex.first?.form, form)
            XCTAssertEqual(restored.state.dex.first?.isShiny, shiny)
            XCTAssertEqual(restored.representativeForm, form)
            XCTAssertEqual(restored.representativeSubject.isShiny, shiny)
        }
    }

    /// 다른 종에는 추가 폼 롤이 없어야 이후 민트 등 기존 난수 결과도 바뀌지 않는다.
    func testNonUnownHatchDoesNotConsumeAnExtraRandomDraw() async throws {
        var original = CompanionState()
        original.inventory = ["mint": 1]
        let s = try store(original, seed: 17)
        var rng = SeededRNG(seed: 17)
        let shiny = rng.next() % PokemonOdds.shinyDenominator == 0
        let nature = PokemonNature.allCases[Int(rng.next() % UInt64(PokemonNature.allCases.count))]
        let profileSeed = rng.next()
        let mintPool = PokemonNature.allCases.filter { $0 != nature }
        let nextNature = mintPool[Int(rng.next() % UInt64(mintPool.count))]

        await s.hatch(baseID: 25)
        XCTAssertNil(s.currentForm)
        XCTAssertEqual(s.currentIsShiny, shiny)
        XCTAssertEqual(s.currentNature, nature)
        XCTAssertEqual(s.state.active?.profile?.seed, profileSeed)
        XCTAssertEqual(s.useMint(), nextNature)
    }

    func testDexDeduplicatesPerLetterAndScopesShinyAndRaisingFlags() throws {
        var original = CompanionState()
        original.dex = [entry(.a), entry(.b), entry(.b, shiny: true)]
        original.active = mon(.c)
        let s = try store(original)
        XCTAssertEqual(s.state.dex.count, 3, "같은 글자의 포획 기록은 각각 보존")
        XCTAssertEqual(s.dexSpecies.count, 1)
        XCTAssertEqual(s.dexSpecies.first?.isShiny, true)
        XCTAssertEqual(s.dexSpecies.first?.isRaising, true)
        XCTAssertEqual(s.state.collectedForms(speciesID: PokemonForm.unownSpeciesID), [.a, .b, .c])
        XCTAssertEqual(s.formSpecies(speciesID: PokemonForm.unownSpeciesID).compactMap(\.form), [.a, .b, .c])
        XCTAssertEqual(s.formSpecies(speciesID: PokemonForm.unownSpeciesID).map(\.isShiny), [false, true, false])
        XCTAssertEqual(s.formSpecies(speciesID: PokemonForm.unownSpeciesID).map(\.isRaising), [false, false, true])
        XCTAssertTrue(s.state.ownsSpecies(201, form: .c))
        XCTAssertFalse(s.state.ownsSpecies(201, form: .z))
        XCTAssertFalse(s.state.ownsShinySpecies(201, form: .a))
        XCTAssertTrue(s.state.ownsShinySpecies(201, form: .b))
        XCTAssertFalse(s.state.ownsShinySpecies(201, form: .c))
    }

    func testRepresentativeUsesExactLetterAndPersistsSelection() throws {
        var original = CompanionState()
        original.language = .en
        original.dex = [entry(.a), entry(.b, shiny: true)]
        let url = try stateURL()
        let s = try store(original, at: url)

        XCTAssertTrue(s.setRepresentativeSpeciesID(201, form: .a))
        XCTAssertFalse(s.representativeSubject.isShiny, "이로치 B가 일반 A의 색을 바꾸면 안 된다")
        XCTAssertEqual(s.representativeDexSpecies?.name, "Unown [A]")
        XCTAssertEqual(s.representativeDexSpecies?.isShiny, false)
        XCTAssertEqual(s.formSpecies(speciesID: PokemonForm.unownSpeciesID).map { s.isRepresentative($0) }, [true, false])
        XCTAssertTrue(s.setRepresentativeSpeciesID(201, form: .b))
        XCTAssertTrue(s.representativeSubject.isShiny)
        XCTAssertEqual(s.representativeDexSpecies?.name, "Unown [B]")
        XCTAssertEqual(s.representativeDexSpecies?.isShiny, true)
        XCTAssertTrue(s.isRepresentative(try XCTUnwrap(s.dexSpecies.first)), "The single species cell marks any representative form")
        XCTAssertEqual(s.formSpecies(speciesID: PokemonForm.unownSpeciesID).map { s.isRepresentative($0) }, [false, true])
        XCTAssertFalse(s.setRepresentativeSpeciesID(201, form: .z))
        XCTAssertEqual(s.representativeForm, .b, "미보유 글자 요청은 기존 선택을 보존")

        let restored = reload(at: url)
        XCTAssertEqual(restored.representativeSpeciesID, 201)
        XCTAssertEqual(restored.representativeForm, .b)
        XCTAssertTrue(restored.representativeSubject.isShiny)
        XCTAssertTrue(restored.setRepresentativeSpeciesID(nil))
        XCTAssertNil(restored.representativeForm)
        XCTAssertNil(restored.representativeDexSpecies)
    }

    func testReleasingActiveLetterPreservesFormProfileAndRepresentative() throws {
        var original = CompanionState()
        original.dex = [entry(.a, shiny: true)]
        original.active = mon(.b)
        original.representativeSpeciesID = 201
        original.representativeForm = .b
        original.usedSinceInstall = FreshEgg.price
        let url = try stateURL()
        let s = try store(original, at: url)
        let profile = try XCTUnwrap(s.state.active?.profile)

        XCTAssertTrue(s.buyFreshEgg())
        XCTAssertEqual(s.representativeSpeciesID, 201)
        XCTAssertEqual(s.representativeForm, .b)
        XCTAssertFalse(s.representativeSubject.isShiny)
        XCTAssertEqual(s.state.dex.count, 2)
        XCTAssertEqual(s.formSpecies(speciesID: PokemonForm.unownSpeciesID).compactMap(\.form), [.a, .b])
        XCTAssertTrue(s.dexSpecies.allSatisfy { !$0.isRaising })
        XCTAssertTrue(s.state.ownsShinySpecies(201, form: .a))
        XCTAssertTrue(s.state.ownsSpecies(201, form: .b))
        let released = try XCTUnwrap(s.state.dex.last)
        XCTAssertTrue(released.isReleased)
        XCTAssertEqual(released.form, .b)
        XCTAssertEqual(released.profile, profile)
        XCTAssertEqual(reload(at: url).representativeForm, .b)
        XCTAssertTrue(s.state.collectedFinals.isEmpty, "놓아줌은 졸업 완료로 세지 않는다")
    }


    func testDetailIndividualsAndRaisingFlagAreScopedToExactLetter() throws {
        var original = CompanionState()
        original.dex = [entry(.a), entry(.b), entry(.b, shiny: true)]
        original.active = mon(.b)
        let s = try store(original)

        XCTAssertEqual(s.formSpecies(speciesID: PokemonForm.unownSpeciesID).map(\.isRaising), [false, true],
                       "이미 졸업한 글자여도 같은 글자를 키우고 있으면 육성 중으로 표시")
        XCTAssertEqual(s.pokemonIndividuals(speciesID: 201).count, 1)
        let bIndividuals = s.pokemonIndividuals(speciesID: 201, form: .b)
        XCTAssertEqual(bIndividuals.count, 3)
        XCTAssertTrue(s.isActiveDexEntry(try XCTUnwrap(bIndividuals.first)))
        XCTAssertTrue(bIndividuals.allSatisfy { $0.form == .b && $0.profile != nil })
        XCTAssertEqual(Set(bIndividuals.compactMap { $0.profile?.instanceID }).count, 3)
        XCTAssertTrue(s.pokemonIndividuals(speciesID: 201, form: .question).isEmpty)
    }

    func testDifferentLettersKeepSpeciesBasedRepeatGrowthAtEveryDifficulty() async throws {
        for difficulty in [0.1, 1.0, 2.0] {
            let s = try store(seed: 17)
            s.setGrowthDifficulty(difficulty)
            await s.hatch(baseID: 201)
            XCTAssertFalse(try XCTUnwrap(s.state.active).hasGrowthBoost)
            let firstForm = try XCTUnwrap(s.currentForm)
            let unboostedThreshold = s.threshold
            s.applyUsage(s.tokensToNext)
            XCTAssertNil(s.state.active)
            XCTAssertEqual(s.state.collectedFinals, ["201:201"])
            var nextEgg = s.state
            nextEgg.pendingHatchID = 201
            nextEgg.pendingForm = firstForm == .a ? .b : .a
            nextEgg.eggUsage = PokemonBalance.eggHatchThreshold
            let repeated = try store(nextEgg)
            repeated.setGrowthDifficulty(difficulty)
            await repeated.hatchIfNeeded()
            XCTAssertEqual(repeated.currentForm, nextEgg.pendingForm)
            XCTAssertNotEqual(repeated.currentForm, firstForm)
            XCTAssertTrue(try XCTUnwrap(repeated.state.active).hasGrowthBoost)
            XCTAssertEqual(repeated.threshold, unboostedThreshold / PokemonBalance.repeatGrowthMultiplier)
            XCTAssertEqual(repeated.state.dex.first?.form, firstForm)
            repeated.applyUsage(repeated.tokensToNext)
            XCTAssertEqual(repeated.state.dex.count, 2)
            XCTAssertTrue(repeated.state.dex.allSatisfy { $0.profile?.level == 100 })
        }
    }

    func testSaveExportAndImportPreserveActiveDexAndRepresentativeForms() throws {
        var original = CompanionState()
        original.active = mon(.question, shiny: true)
        original.dex = [entry(.a), entry(.exclamation, shiny: true)]
        original.representativeSpeciesID = 201
        original.representativeForm = .exclamation
        let source = try store(original)
        let data = try source.exportedSaveData(appVersion: "test", deviceName: "Source")
        let envelope = try SaveTransfer.decode(data)
        let destinationURL = try stateURL()
        let destination = try store(at: destinationURL)

        try destination.applySave(envelope, todayTokensByProvider: [:], todayDate: "2026-09-11",
                                  hasUsageData: false)
        let restored = reload(at: destinationURL)
        XCTAssertEqual(restored.state.active?.form, .question)
        XCTAssertEqual(restored.state.active?.isShiny, true)
        XCTAssertEqual(restored.state.dex.compactMap(\.form), [.a, .exclamation])
        XCTAssertEqual(restored.state.dex.map(\.isShiny), [false, true])
        XCTAssertEqual(restored.representativeForm, .exclamation)
        XCTAssertTrue(restored.representativeSubject.isShiny)
    }

    /// 실제 update → pre-roll 경로가 글자를 저장하고, 재실행 뒤에도 같은 글자로 부화해야 한다.
    func testPrefetchPersistsLetterAndHatchConsumesItAfterRNGChanges() async throws {
        var original = CompanionState()
        original.installBaselineSet = true
        original.lastDate = "d1"
        let seed = try XCTUnwrap((UInt64(0)..<1_000).first { seed in
            var rng = SeededRNG(seed: seed)
            _ = rng.next()
            return rng.next() % 56 / 2 != 0
        })
        var prefetchRNG = SeededRNG(seed: seed)
        _ = prefetchRNG.next() // 종 선택
        let expectedForm = PokemonForm.unownLetters[Int(prefetchRNG.next() % 56 / 2)]
        let signal = UnownPrefetchSignal()
        let url = try stateURL()
        let s = try store(original, seed: seed, at: url,
                          provider: UnownPrefetchProvider(lineRequested: signal))

        s.update(todayTokensByProvider: ["test": 1_000], todayDate: "d1", monthTotal: 0,
                 burnTier: .idle, limitWarning: false, hasUsageData: true)
        await signal.wait() // 프리패치가 종·글자 저장 후 라인 예열에 진입했다.
        XCTAssertNil(s.state.active)
        XCTAssertEqual(s.state.pendingHatchID, 201)
        XCTAssertEqual(s.state.pendingForm, expectedForm)
        var persisted = try JSONDecoder().decode(CompanionState.self, from: Data(contentsOf: url))
        XCTAssertEqual(persisted.pendingForm, expectedForm)

        // 새 RNG라면 원래 다른 글자가 나오는 시드로 재실행해도 pending 글자를 사용한다.
        let restartedSeed = try XCTUnwrap((UInt64(0)..<1_000).first { seed in
            var rng = SeededRNG(seed: seed)
            _ = rng.next() // shiny
            _ = rng.next() // nature
            _ = rng.next() // profile seed
            return PokemonForm.unownLetters[Int(rng.next() % 56 / 2)] != expectedForm
        })
        persisted.eggUsage = PokemonBalance.eggHatchThreshold
        persisted.usedSinceInstall = FreshEgg.price
        let restarted = try store(persisted, seed: restartedSeed)
        await restarted.hatchIfNeeded()

        XCTAssertEqual(restarted.currentForm, expectedForm)
        XCTAssertNil(restarted.state.pendingHatchID)
        XCTAssertNil(restarted.state.pendingForm)
        XCTAssertTrue(restarted.buyFreshEgg())
        XCTAssertNil(restarted.state.active)
        XCTAssertNil(restarted.state.pendingHatchID)
        XCTAssertNil(restarted.state.pendingForm, "새 알로 이전 글자가 이월되면 안 된다")
    }

    func testLegacyPendingUnownKeepsDefaultAAtHatch() async throws {
        let legacy = Data(#"{"pendingHatchID":201,"eggUsage":5000000}"#.utf8)
        let decoded = try JSONDecoder().decode(CompanionState.self, from: legacy)
        XCTAssertEqual(decoded.pendingForm, .a)
        let s = try store(decoded, seed: 17)

        await s.hatchIfNeeded()
        XCTAssertEqual(s.currentForm, .a)
        XCTAssertNil(s.state.pendingForm)
    }

    func testPendingLetterSurvivesFailedLineLoadAndHatchesOnRetry() async throws {
        var original = CompanionState()
        original.pendingHatchID = 201
        original.pendingForm = .question
        original.eggUsage = PokemonBalance.eggHatchThreshold + 123
        let url = try stateURL()
        let s = try store(original, seed: 17, at: url, provider: UnownRetryProvider())

        await s.hatchIfNeeded() // 첫 라인 요청은 오프라인 실패.
        XCTAssertNil(s.state.active)
        XCTAssertFalse(s.isHatching)
        XCTAssertEqual(s.state.pendingHatchID, 201)
        XCTAssertEqual(s.state.pendingForm, .question)
        XCTAssertEqual(s.state.eggUsage, original.eggUsage)
        s.setLanguage(.ko) // 다음 일반 저장에서도 예열한 종·글자가 유실되지 않아야 한다.
        let saved = reload(at: url)
        XCTAssertEqual(saved.state.pendingHatchID, 201)
        XCTAssertEqual(saved.state.pendingForm, .question)

        await s.hatchIfNeeded()
        XCTAssertEqual(s.currentSpeciesID, 201)
        XCTAssertEqual(s.currentForm, .question)
        XCTAssertEqual(s.state.active?.usedAtStage, 123)
        XCTAssertNil(s.state.pendingHatchID)
        XCTAssertNil(s.state.pendingForm)
    }

    func testSanitizationClearsPendingLetterWithoutMatchingEgg() {
        var original = CompanionState()
        original.active = mon(.b)
        original.pendingHatchID = 201
        original.pendingForm = .question
        let activeState = SaveTransfer.sanitized(original)
        XCTAssertEqual(activeState.active?.form, .b)
        XCTAssertNil(activeState.pendingHatchID)
        XCTAssertNil(activeState.pendingForm)

        original.active = nil
        original.pendingHatchID = 25
        XCTAssertNil(SaveTransfer.sanitized(original).pendingForm)
        original.pendingHatchID = nil
        XCTAssertNil(SaveTransfer.sanitized(original).pendingForm)
    }

    func testSaveExportAndImportPreservePendingEggLetter() throws {
        var original = CompanionState()
        original.pendingHatchID = 201
        original.pendingForm = .exclamation
        original.eggUsage = 1_234
        let source = try store(original)
        let data = try source.exportedSaveData(appVersion: "test", deviceName: "Source")
        let destinationURL = try stateURL()
        let destination = try store(at: destinationURL)

        try destination.applySave(SaveTransfer.decode(data), todayTokensByProvider: [:],
                                  todayDate: "2026-09-11", hasUsageData: false)
        let restored = reload(at: destinationURL)
        XCTAssertNil(restored.state.active)
        XCTAssertEqual(restored.state.pendingHatchID, 201)
        XCTAssertEqual(restored.state.pendingForm, .exclamation)
        XCTAssertEqual(restored.state.eggUsage, 1_234)
    }
}
