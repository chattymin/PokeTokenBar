import XCTest
@testable import PokeTokenBar

private actor MigratingNameProvider: PokeProviding {
    var value: EvoLine
    var offline = false
    private(set) var calls = 0
    init(_ names: [Int: [String: String]]) {
        value = EvoLine(baseID: 1, tree: EvoNode(speciesID: 1, children: [EvoNode(speciesID: 2, children: [])]),
                        rarity: .common, names: names)
    }
    func configure(names: [Int: [String: String]], offline: Bool = false) {
        value = EvoLine(baseID: 1, tree: value.tree, rarity: .common, names: names)
        self.offline = offline
    }
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        calls += 1
        if offline { throw URLError(.notConnectedToInternet) }
        return value
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
}

@MainActor
final class DexNameMigrationTests: XCTestCase {
    let allNames = [1: ["ko": "이상해씨", "en": "Bulbasaur", "it": "Bulbasaur"],
                    2: ["ko": "이상해풀", "en": "Ivysaur", "it": "Ivysaur"]]

    private func entry(_ id: String = "old-catch") -> DexEntry {
        DexEntry(id: id, baseID: 1, finalID: 2, chainOrder: [1, 2], rarity: .common,
                 caughtAt: Date(timeIntervalSince1970: 123), isShiny: true, nature: .brave,
                 names: [1: ["en": "Bulbasaur"], 2: ["en": "Ivysaur"]])
    }

    private func fixture(_ entries: [DexEntry], legacy: Bool = true) throws -> URL {
        var state = CompanionState()
        state.dex = entries
        state.language = .ko
        state.usedSinceInstall = 1234567
        state.inventory = ["rareCandy": 3]
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        if legacy {
            json["dex"] = try XCTUnwrap(json["dex"] as? [[String: Any]]).map { row in
                var row = row
                row.removeValue(forKey: "namesVersion")
                return row
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dex-language-\(UUID()).json")
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        return url
    }

    func testLegacyNamedEntriesRefreshAllLanguagesOnceAndPreserveProgress() async throws {
        let url = try fixture([entry(), entry("second-catch")])
        defer { try? FileManager.default.removeItem(at: url) }
        let provider = MigratingNameProvider(allNames)
        let store = CompanionStore(provider: provider, fileURL: url)
        let old = try XCTUnwrap(store.state.dex.first)
        XCTAssertNil(old.namesVersion, "Old JSON did not encode a name version")
        XCTAssertEqual(store.dexStoredChainNames(old)?[1], "Bulbasaur")
        await store.backfillMissingDexNames()
        XCTAssertEqual(store.state.dex.count, 2)
        XCTAssertEqual(store.state.dex[0].id, old.id)
        XCTAssertEqual(store.state.dex[0].caughtAt, old.caughtAt)
        XCTAssertEqual(store.state.dex[0].isShiny, old.isShiny)
        XCTAssertEqual(store.state.dex[0].nature, old.nature)
        XCTAssertEqual(store.state.usedSinceInstall, 1234567)
        XCTAssertEqual(store.state.inventory["rareCandy"], 3)
        XCTAssertTrue(store.state.dex.allSatisfy { !$0.needsNamesRefresh })
        XCTAssertEqual(store.dexStoredChainNames(store.state.dex[0])?[1], "이상해씨")
        XCTAssertEqual(PokemonNameLocalization.resolve(store.state.dex[0].names![2]!, preferredCodes: ["it"]), "Ivysaur")
        _ = await store.dexResolveChainNames(old) // A mounted row can still hold its old value.
        await store.backfillMissingDexNames()
        let calls = await provider.calls
        XCTAssertEqual(calls, 1, "Duplicate catches and stale row values must reuse the refreshed names")

        let restored = CompanionStore(provider: provider, fileURL: url)
        restored.setLanguage(.pt) // No Portuguese names in the API response: English is complete fallback.
        await restored.backfillMissingDexNames()
        XCTAssertEqual(restored.dexStoredChainNames(restored.state.dex[0])?[1], "Bulbasaur")
        let restoredCalls = await provider.calls
        XCTAssertEqual(restoredCalls, 1, "Absent translation is not an expired cache")
    }

    func testOfflineLegacyCacheRemainsVisibleAndRetriesAfterRecovery() async throws {
        let url = try fixture([entry()])
        defer { try? FileManager.default.removeItem(at: url) }
        let provider = MigratingNameProvider(allNames)
        await provider.configure(names: allNames, offline: true)
        let store = CompanionStore(provider: provider, fileURL: url)
        let old = store.state.dex[0]
        let fallback = await store.dexResolveChainNames(old)
        XCTAssertEqual(fallback, [1: "Bulbasaur", 2: "Ivysaur"])
        XCTAssertNil(store.state.dex[0].namesVersion)
        await provider.configure(names: allNames)
        await store.backfillMissingDexNames()
        XCTAssertEqual(store.dexStoredChainNames(store.state.dex[0])?[2], "이상해풀")
        XCTAssertFalse(store.state.dex[0].needsNamesRefresh)
    }

    func testPartialResponsePreservesOldNamesWithoutMarkingMigrationComplete() async throws {
        let url = try fixture([entry()])
        defer { try? FileManager.default.removeItem(at: url) }
        let provider = MigratingNameProvider([1: allNames[1]!])
        let store = CompanionStore(provider: provider, fileURL: url)
        await store.backfillMissingDexNames()
        XCTAssertEqual(store.dexStoredChainNames(store.state.dex[0]), [1: "이상해씨", 2: "Ivysaur"])
        XCTAssertTrue(store.state.dex[0].needsNamesRefresh)
        await provider.configure(names: allNames)
        await store.backfillMissingDexNames()
        XCTAssertFalse(store.state.dex[0].needsNamesRefresh)
        XCTAssertEqual(store.state.dex[0].names?[2]?["it"], "Ivysaur")
    }

    func testNewNamesSkipMigrationButEmptyAndMissingSpeciesRetry() throws {
        var fresh = entry()
        XCTAssertFalse(fresh.needsNamesRefresh)
        let roundTrip = try JSONDecoder().decode(DexEntry.self, from: JSONEncoder().encode(fresh))
        XCTAssertFalse(roundTrip.needsNamesRefresh)
        fresh.names = [:]
        XCTAssertTrue(fresh.needsNamesRefresh)
        fresh.names = [1: ["en": "Bulbasaur"]]
        XCTAssertTrue(fresh.needsNamesRefresh)
        fresh.namesVersion = nil
        XCTAssertTrue(fresh.needsNamesRefresh)
    }
}
