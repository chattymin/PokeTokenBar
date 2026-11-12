import Foundation
import XCTest
@testable import PokeTokenBar

private struct ChineseOfflineProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

final class SimplifiedChineseTests: XCTestCase {
    func testSystemLanguageSelectsSimplifiedChineseWithoutCapturingTraditionalChinese() {
        for tag in ["zh", "zh-CN", "zh-SG", "zh-Hans", "zh-Hans-CN", "zh-Hans-SG",
                    "zh-Hans-TW", "ZH-hAnS-hK", "zh_Hans_MO", "zh_CN"] {
            XCTAssertEqual(AppLanguage.systemDefault(for: tag), .zhHans, tag)
        }
        for tag in ["zh-Hant", "zh-TW", "zh-HK", "zh-MO", "zh-Hant-CN", "zh-Hant-SG",
                    "zh_Hant_CN", "zh-MY", "zh-XX"] {
            XCTAssertEqual(AppLanguage.systemDefault(for: tag), .en, tag)
        }
        for tag: String? in [nil, "", "it-IT"] {
            XCTAssertEqual(AppLanguage.systemDefault(for: tag), .en)
        }
    }

    func testExistingLanguageIdentifiersAndSystemDefaultsStayCompatible() throws {
        let existing: [(String, AppLanguage)] = [
            ("ko", .ko), ("en", .en), ("ja", .ja), ("es", .es),
            ("fr", .fr), ("pt", .pt), ("de", .de), ("ru", .ru),
        ]
        XCTAssertEqual(Array(AppLanguage.allCases.dropLast()), existing.map(\.1))
        for (code, language) in existing {
            XCTAssertEqual(try JSONDecoder().decode(AppLanguage.self, from: Data("\"\(code)\"".utf8)), language)
            XCTAssertEqual(AppLanguage.systemDefault(for: "\(code)-US"), language)
        }
        XCTAssertEqual(AppLanguage.zhHans.rawValue, "zh-Hans")
        XCTAssertEqual(AppLanguage.zhHans.label, "简体中文")
        XCTAssertEqual(AppLanguage.zhHans.apiCodes, ["zh-hans"])
        XCTAssertTrue(PokeAPIClient.langCodes.contains("zh-hans"))
    }

    func testChineseNamesUseTheSelectedScriptAndExistingEnglishFallback() {
        let names = ["en": "Pikachu", "zh-Hans": "皮卡丘", "zh-Hant": "皮卡丘"]
        XCTAssertEqual(AppLanguage.zhHans.resolveName(names), "皮卡丘")
        XCTAssertEqual(AppLanguage.en.resolveName(names), "Pikachu")
        XCTAssertEqual(AppLanguage.zhHans.resolveName(["zh_Hans": " 电 ", "en": "Electric"]), "电")
        XCTAssertEqual(AppLanguage.zhHans.resolveName(["zh-hans": " \n", "en": "Electric"]), "Electric")
        XCTAssertEqual(AppLanguage.zhHans.resolveName(["zh-hant": "電", "en": "Electric"]), "Electric")
        XCTAssertNil(AppLanguage.zhHans.resolveName(["zh-hant": "電"]))
    }

    func testNatureNamesUseMainSeriesSimplifiedChineseTerms() {
        // Main-series names, also present in PokéAPI's nature_names (language 12).
        let expected = [
            "勤奋", "怕寂寞", "勇敢", "固执", "顽皮",
            "大胆", "坦率", "悠闲", "淘气", "乐天",
            "胆小", "急躁", "认真", "爽朗", "天真",
            "内敛", "慢吞吞", "冷静", "害羞", "马虎",
            "温和", "温顺", "自大", "慎重", "浮躁",
        ]
        XCTAssertEqual(PokemonNature.allCases.map { $0.name(.zhHans) }, expected)
    }

    func testItemsRegionsAndPokemonTerminology() {
        let l = L(.zhHans)
        XCTAssertEqual(l.itemName(.rareCandy), "神奇糖果")
        XCTAssertEqual(l.itemName(.mint), "薄荷")
        XCTAssertEqual(l.itemName(.shinyCharm), "闪耀护符")
        XCTAssertEqual(l.eggName(nil), "宝可梦的蛋")
        XCTAssertEqual(l.moveMethod(.init(method: "light-ball-egg", level: 0)), "电气球遗传")
        XCTAssertEqual([PokedexRegion.kanto, .johto, .hoenn, .sinnoh, .unova].map(l.regionName),
                       ["关都", "城都", "丰缘", "神奥", "合众"])
        XCTAssertTrue(l.notifDittoRevealBody("皮卡丘").contains("百变怪"))
    }

    func testChineseDateAndRelativeTimeFormatting() {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = AppLanguage.zhHans.displayLocale
        formatter.unitsStyle = .full
        let relative = formatter.localizedString(from: DateComponents(hour: -2))
        XCTAssertTrue(relative.contains("小时"), relative)
        XCTAssertFalse(relative.contains("小時"), relative)
        let dateFormatter = DateFormatter()
        dateFormatter.locale = AppLanguage.zhHans.displayLocale
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormatter.dateStyle = .long
        let date = dateFormatter.string(from: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertTrue(date.contains("年") && date.contains("月") && date.contains("日"), date)
    }

    @MainActor
    func testSwitchingLanguagesChangesOnlyThePersistedLanguageAndPreservesProgress() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ChineseSave-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "ChineseSave-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = directory.appendingPathComponent("state.json")
        var state = CompanionState()
        state.language = .en
        state.installBaselineSet = true
        state.usedSinceInstall = 80_000_000
        state.spentTokens = 1_000_000
        state.inventory = [ItemKind.rareCandy.rawValue: 3, ItemKind.mint.rawValue: 2]
        state.active = MonState(baseID: 25, pathIDs: [25, 26], stageIndex: 0,
                                usedAtStage: 12345, rarity: .common, totalForms: 2)
        state.dex = [DexEntry(baseID: 25, finalID: 25, chainOrder: [25], rarity: .common,
                              caughtAt: Date(timeIntervalSince1970: 1_700_000_000),
                              names: [25: ["en": "Pikachu", "zh-hans": "皮卡丘"]])]
        try JSONEncoder().encode(state).write(to: file)
        let store = CompanionStore(provider: ChineseOfflineProvider(), fileURL: file, defaults: defaults)
        // Finish the normal load migrations before comparing language changes.
        store.setLanguage(.en)
        let before = try JSONEncoder().encode(store.state)
        let progress = store.tokensToNext
        let wallet = store.availableTokens
        let price = store.price(of: .rareCandy)
        for language in [AppLanguage.zhHans, .en, .zhHans] {
            store.setLanguage(language)
            let saved = try Data(contentsOf: file)
            let restored = try JSONDecoder().decode(CompanionState.self, from: saved)
            XCTAssertEqual(restored.language, language)
            var old = try XCTUnwrap(JSONSerialization.jsonObject(with: before) as? [String: Any])
            var new = try XCTUnwrap(JSONSerialization.jsonObject(with: saved) as? [String: Any])
            old.removeValue(forKey: "language")
            new.removeValue(forKey: "language")
            XCTAssertEqual(old as NSDictionary, new as NSDictionary)
            XCTAssertEqual(store.tokensToNext, progress)
            XCTAssertEqual(store.availableTokens, wallet)
            XCTAssertEqual(store.price(of: .rareCandy), price)
            XCTAssertEqual(store.dexSpecies.first?.name, language == .zhHans ? "皮卡丘" : "Pikachu")
        }
        XCTAssertEqual(CompanionStore(provider: ChineseOfflineProvider(), fileURL: file,
                                     defaults: defaults).language, .zhHans)
    }

    func testCachedChineseMetadataRemainsAvailableOfflineAfterLanguageSwitch() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ChineseNames-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let response = Data(#"{"names":[{"name":"Electric","language":{"name":"en"}},{"name":"电","language":{"name":"zh-Hans"}}]}"#.utf8)
        let resource = PokemonNameResource(kind: .type, name: "electric")
        let online = PokemonNameClient(directory: directory, fetch: { _ in response })
        let names = try await online.names(for: resource)
        XCTAssertEqual(AppLanguage.en.resolveName(names), "Electric")
        XCTAssertEqual(AppLanguage.zhHans.resolveName(names), "电")
        let offline = PokemonNameClient(directory: directory, fetch: { _ in throw URLError(.notConnectedToInternet) })
        let cached = try await offline.names(for: resource)
        XCTAssertEqual(AppLanguage.zhHans.resolveName(cached), "电")
        XCTAssertEqual(cached, names)
    }

    /// Opt-in smoke check of the existing runtime source; no bulk names or assets are bundled.
    func testLivePokeAPIChineseNames() async throws {
        guard ProcessInfo.processInfo.environment["PTB_VERIFY_ZH_API"] == "1" else {
            throw XCTSkip("Set PTB_VERIFY_ZH_API=1 to verify live PokéAPI translations")
        }
        struct Names: Decodable { let names: [NameDTO] }
        let data = try await PokemonNameClient.download(URL(string: "https://pokeapi.co/api/v2/pokemon-species/25/")!)
        let species = try JSONDecoder().decode(Names.self, from: data)
        XCTAssertEqual(AppLanguage.zhHans.resolveName(PokemonNameLocalization.collect(species.names)), "皮卡丘")
        let client = PokemonNameClient(directory: nil)
        let samples: [(PokemonNameResource, String)] = [
            (.init(kind: .type, name: "electric"), "电"),
            (.init(kind: .ability, name: "static"), "静电"),
            (.init(kind: .move, name: "thunderbolt"), "十万伏特"),
        ]
        for (resource, expected) in samples {
            let names = try await client.names(for: resource)
            XCTAssertEqual(AppLanguage.zhHans.resolveName(names), expected, resource.cacheKey)
        }
    }
}
