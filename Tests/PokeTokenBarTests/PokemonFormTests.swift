import XCTest
@testable import PokeTokenBar

private enum FormTestError: Error { case offline }

private func node(_ id: Int, _ children: [EvoNode] = []) -> EvoNode { EvoNode(speciesID: id, children: children) }

/// Burmy (#412) branches into Wormadam (#413, cloaks) and Mothim (#414, single look).
private let burmyLine = EvoLine(baseID: 412, tree: node(412, [node(413), node(414)]), rarity: .common,
                                names: [412: ["en": "Burmy", "fr": "Cheniti"], 413: ["en": "Wormadam"],
                                        414: ["en": "Mothim"]])
private let shayminLine = EvoLine(baseID: 492, tree: node(492), rarity: .legendary,
                                  names: [492: ["en": "Shaymin", "fr": "Shaymin"]])
private let dittoLine = EvoLine(baseID: 132, tree: node(132), rarity: .rare, names: [132: ["en": "Ditto"]])
private let shellosLine = EvoLine(baseID: 422, tree: node(422, [node(423)]), rarity: .common,
                                  names: [422: ["en": "Shellos"], 423: ["en": "Gastrodon"]])

private struct FormTestProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        switch baseSpeciesID {
        case 412: return burmyLine
        case 492: return shayminLine
        case 422: return shellosLine
        case PokemonOdds.dittoSpeciesID: return dittoLine
        default: throw FormTestError.offline
        }
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { throw FormTestError.offline }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { throw FormTestError.offline }
}

private struct FixedNames: PokemonNameProviding {
    let names: [String: String]
    func names(for resource: PokemonNameResource) async throws -> [String: String] { names }
}

private actor FormNameServer {
    private(set) var urls: [URL] = []
    let response: Data
    init(_ response: Data) { self.response = response }
    func fetch(_ url: URL) async throws -> Data {
        urls.append(url)
        return response
    }
}

@MainActor
final class PokemonFormTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let sky = PokemonForm("sky"), land = PokemonForm("land")
    private let sandy = PokemonForm("sandy"), plant = PokemonForm("plant")

    private func store(_ state: CompanionState, seed: UInt64 = 7) throws -> CompanionStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("forms-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("companion-state.json")
        try JSONEncoder().encode(state).write(to: url)
        let suite = "form-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(1.0, forKey: "growthDifficulty")
        defaults.set(1.0, forKey: "shopDifficulty")
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let date = now
        return CompanionStore(provider: FormTestProvider(), clock: { date }, fileURL: url,
                              rng: SeededRNG(seed: seed), dittoDisguiseRollingEnabled: false, defaults: defaults)
    }

    private func burmy(_ path: [Int], form: PokemonForm?, shiny: Bool = false) -> DexEntry {
        DexEntry(baseID: 412, finalID: path.last!, chainOrder: path, rarity: .common, caughtAt: now,
                 isShiny: shiny, nature: .brave, form: form)
    }

    // MARK: Catalog

    func testCatalogListsDefaultFirstWithinTheHatchableRange() {
        XCTAssertEqual(PokemonForm.catalog.count, 23)
        for (speciesID, entries) in PokemonForm.catalog {
            XCTAssertTrue(PokemonAssets.animatedSpeciesIDs.contains(speciesID))
            XCTAssertGreaterThanOrEqual(entries.count, 2, "#\(speciesID)")
            XCTAssertEqual(Set(entries.map(\.form)).count, entries.count, "#\(speciesID) repeats a form")
            XCTAssertEqual(entries.first?.formID, speciesID, "#\(speciesID) default is the species' own form")
            XCTAssertTrue(entries.dropFirst().allSatisfy { $0.formID > 10000 }, "#\(speciesID)")
        }
        XCTAssertEqual(PokemonForm.forms(speciesID: 493).count, 18)
        XCTAssertEqual(PokemonForm.forms(speciesID: 492), [land, sky])
        XCTAssertFalse(PokemonForm.hasForms(speciesID: 414), "Mothim's cloaks share one sprite")
        XCTAssertFalse(PokemonForm.hasForms(speciesID: 172), "Spiky-eared Pichu has no Gen V animation")
        XCTAssertFalse(PokemonForm.hasForms(speciesID: 592), "Gender differences are not forms")
    }

    func testLinesCarryFormsFromTheirBaseEvenWhenTheBaseLooksTheSame() {
        XCTAssertEqual(PokemonForm.formSpecies(baseID: 412), [412, 413])
        XCTAssertEqual(PokemonForm.lineForms(baseID: 412), [plant, sandy, PokemonForm("trash")])
        XCTAssertEqual(PokemonForm.formSpecies(baseID: 420), [421])
        XCTAssertEqual(PokemonForm.lineForms(baseID: 420), [PokemonForm("overcast"), PokemonForm("sunshine")])
        XCTAssertEqual(PokemonForm.lineForms(baseID: 554), [PokemonForm("standard"), PokemonForm("zen")])
        XCTAssertEqual(PokemonForm.lineForms(baseID: 1), [])
        XCTAssertEqual(PokemonForm.resolved(baseID: 420, form: nil), PokemonForm("overcast"))
        XCTAssertNil(PokemonForm.resolved(speciesID: 420, form: PokemonForm("sunshine")), "Cherubi has one look")
    }

    func testFormResolvesPerSpeciesOfTheLine() {
        XCTAssertEqual(PokemonForm.resolved(speciesID: 412, form: sandy), sandy)
        XCTAssertEqual(PokemonForm.resolved(speciesID: 413, form: sandy), sandy)
        XCTAssertNil(PokemonForm.resolved(speciesID: 414, form: sandy))
        XCTAssertEqual(PokemonForm.resolved(speciesID: 492, form: nil), land)
        XCTAssertEqual(PokemonForm.resolved(speciesID: 492, form: PokemonForm("future")), land)
        XCTAssertNil(PokemonForm.resolved(speciesID: 25, form: sky))
    }

    // MARK: Sprites

    func testVarietyFormsUseTheVarietyPNGAndTheFormGIF() {
        let base = "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon"
        XCTAssertEqual(SpriteStore.spriteURL(speciesID: 492, animated: false, shiny: false, form: sky).absoluteString,
                       "\(base)/10006.png")
        XCTAssertEqual(SpriteStore.spriteURL(speciesID: 492, animated: false, shiny: true, form: sky).absoluteString,
                       "\(base)/shiny/10006.png")
        XCTAssertEqual(SpriteStore.spriteURL(speciesID: 492, animated: true, shiny: true, form: sky).absoluteString,
                       "\(base)/versions/generation-v/black-white/animated/shiny/492-sky.gif")
        XCTAssertEqual(SpriteStore.spriteURL(speciesID: 412, animated: false, shiny: false, form: sandy).absoluteString,
                       "\(base)/412-sandy.png")
        XCTAssertEqual(SpriteStore.spriteURL(speciesID: 492, animated: false, shiny: false, form: land).absoluteString,
                       "\(base)/492.png")
        XCTAssertEqual(SpriteStore.spriteURL(speciesID: 414, animated: true, shiny: false, form: sandy).absoluteString,
                       "\(base)/versions/generation-v/black-white/animated/414.gif")
    }

    func testCacheKeysSeparateFormsAndKeepDefaultKeys() {
        XCTAssertEqual(SpriteStore.cacheKey(speciesID: 492, animated: false, shiny: false, form: sky), "492-sky-s")
        XCTAssertEqual(SpriteStore.cacheKey(speciesID: 492, animated: true, shiny: true, form: sky), "492-sky-sha")
        XCTAssertEqual(SpriteStore.cacheKey(speciesID: 492, animated: false, shiny: false, form: land),
                       SpriteStore.cacheKey(speciesID: 492, animated: false, shiny: false))
        XCTAssertEqual(SpriteStore.cacheKey(speciesID: 413, animated: false, shiny: false, form: sandy), "413-sandy-s")
    }

    /// Opt-in: every catalogued sprite, normal and shiny, still exists on PokéAPI.
    func testEveryCataloguedSpriteExistsOnPokeAPI() async throws {
        guard ProcessInfo.processInfo.environment["PTB_PARITY"] == "1" else {
            throw XCTSkip("set PTB_PARITY=1 to check PokéAPI sprites for every form")
        }
        for (speciesID, forms) in PokemonForm.catalog.mapValues({ $0.map(\.form) }) {
            for form in forms {
                for animated in [false, true] {
                    for shiny in [false, true] {
                        var request = URLRequest(url: SpriteStore.spriteURL(speciesID: speciesID, animated: animated,
                                                                            shiny: shiny, form: form))
                        request.httpMethod = "HEAD"
                        let (_, response) = try await URLSession.shared.data(for: request)
                        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200, "\(request.url!)")
                    }
                }
            }
        }
    }

    // MARK: Saves

    func testSavesWrittenBeforeGenericFormsKeepTheirUnownLetters() throws {
        let json = """
        {"pendingHatchID":201,"pendingUnownForm":"k","representativeSpeciesID":201,"representativeUnownForm":"q",
         "active":{"baseID":201,"pathIDs":[201],"stageIndex":0,"usedAtStage":0,"rarity":"common","totalForms":1,
                   "unownForm":"z"},
         "dex":[{"baseID":201,"finalID":201,"chainOrder":[201],"rarity":"common","unownForm":"q"}]}
        """
        let state = try JSONDecoder().decode(CompanionState.self, from: Data(json.utf8))
        XCTAssertEqual(state.pendingForm, .k)
        XCTAssertEqual(state.active?.form, .z)
        XCTAssertEqual(state.dex.first?.form, .q)
        XCTAssertEqual(state.representativeForm, .q)

        let reencoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        XCTAssertEqual((reencoded["active"] as? [String: Any])?["form"] as? String, "z")
        XCTAssertEqual(reencoded["representativeForm"] as? String, "q")
    }

    func testStoredFormIsNormalizedAgainstTheLine() throws {
        let json = """
        {"active":{"baseID":412,"pathIDs":[412,413],"stageIndex":1,"usedAtStage":0,"rarity":"common",
                   "totalForms":2,"form":"sky"},
         "dex":[{"baseID":1,"finalID":1,"chainOrder":[1],"rarity":"common","form":"sandy"}]}
        """
        let state = try JSONDecoder().decode(CompanionState.self, from: Data(json.utf8))
        XCTAssertEqual(state.active?.form, plant, "A form from another line falls back to the line default")
        XCTAssertNil(state.dex.first?.form, "Lines without forms store none")
    }

    // MARK: Collection

    func testEvolutionKeepsTheCloakAndMothimKeepsItsSingleLook() {
        var state = CompanionState()
        state.active = MonState(baseID: 412, pathIDs: [412, 413], stageIndex: 1, usedAtStage: 0,
                                rarity: .common, totalForms: 2, form: sandy)
        state.dex = [burmy([412, 414], form: sandy)]
        XCTAssertTrue(state.ownsSpecies(413, form: sandy))
        XCTAssertFalse(state.ownsSpecies(413, form: plant))
        XCTAssertTrue(state.ownsSpecies(414))
        XCTAssertEqual(state.collectedForms(speciesID: 412), [sandy])
        XCTAssertEqual(state.collectedForms(speciesID: 413), [sandy])
        XCTAssertEqual(state.collectedForms(speciesID: 414), [])
    }

    func testLineFormCountsOnlyOnceEverySpeciesShowingItIsOwned() {
        var state = CompanionState()
        state.dex = [burmy([412, 414], form: sandy)]
        XCTAssertFalse(state.collectedLineForms(baseID: 412).contains(sandy), "Sandy Wormadam is still missing")
        state.dex.append(burmy([412, 413], form: sandy))
        XCTAssertEqual(state.collectedLineForms(baseID: 412), [sandy])
        XCTAssertEqual(state.collectedLineForms(baseID: 201), [])
    }

    func testDetailListsOwnedFormsAndMainDexKeepsOneCell() throws {
        var state = CompanionState()
        state.dex = [burmy([412, 413], form: sandy), burmy([412, 413], form: plant, shiny: true),
                     burmy([412, 414], form: PokemonForm("trash"))]
        let s = try store(state)
        XCTAssertEqual(s.dexSpecies.map(\.id), [412, 413, 414])
        XCTAssertEqual(s.formSpecies(speciesID: 413).map(\.form), [plant, sandy])
        XCTAssertEqual(s.formSpecies(speciesID: 413).map(\.isShiny), [true, false])
        XCTAssertEqual(s.formSpecies(speciesID: 412).map(\.form), [plant, sandy, PokemonForm("trash")])
        XCTAssertTrue(s.formSpecies(speciesID: 414).isEmpty)

        XCTAssertTrue(s.setRepresentativeSpeciesID(413, form: sandy))
        XCTAssertEqual(s.representativeSubject.form, sandy)
        XCTAssertFalse(s.setRepresentativeSpeciesID(413, form: PokemonForm("trash")), "Trash Wormadam is not owned")
        XCTAssertEqual(s.representativeDexSpecies?.form, sandy)
    }

    // MARK: Hatch

    func testHatchUsesThePreparedFormOfAnyLine() async throws {
        var state = CompanionState()
        state.pendingHatchID = 492
        state.pendingForm = sky
        state.eggUsage = PokemonBalance.eggHatchThreshold
        let s = try store(state)
        await s.hatchIfNeeded()
        XCTAssertEqual(s.state.active?.baseID, 492)
        XCTAssertEqual(s.state.active?.form, sky)
        XCTAssertEqual(s.currentForm, sky)
        XCTAssertNil(s.state.pendingForm)
    }

    func testEvolutionNamesTheFormLikeHatchAndGraduation() async throws {
        let east = PokemonForm("east")
        var state = CompanionState()
        state.language = .en
        state.pendingHatchID = 422
        state.pendingForm = east
        state.eggUsage = PokemonBalance.eggHatchThreshold
        let s = try store(state)
        await s.hatchIfNeeded()
        s.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 2, stageIndex: 0))
        XCTAssertEqual(s.state.active?.currentID, 423)
        XCTAssertEqual(s.justEvolvedTo,
                       PokemonForm.displayName("Gastrodon", speciesID: 423, form: east, language: .en))
        XCTAssertNotEqual(s.justEvolvedTo, "Gastrodon", "East Sea Gastrodon must not read as the default West Sea")
    }

    func testHatchWithoutPreparationRollsAmongTheLineForms() async throws {
        var seen = Set<PokemonForm>()
        for seed in UInt64(1)...24 {
            let s = try store(CompanionState(), seed: seed)
            await s.hatch(baseID: 412)
            let form = try XCTUnwrap(s.state.active?.form)
            XCTAssertTrue(PokemonForm.lineForms(baseID: 412).contains(form))
            seen.insert(form)
        }
        XCTAssertEqual(seen, Set(PokemonForm.lineForms(baseID: 412)))
    }

    func testRevealedDittoDropsTheDisguiseForm() async throws {
        let json = """
        {"installBaselineSet":true,"usedSinceInstall":1000000000,"lastDate":"d1","dex":[],"collectedFinals":[],
         "active":{"baseID":412,"pathIDs":[412],"stageIndex":0,"usedAtStage":900000000,"rarity":"common",
                   "totalForms":2,"form":"sandy","dittoDisguise":412,"dittoRevealed":false}}
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("form-ditto-\(UUID().uuidString).json")
        try Data(json.utf8).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let suite = "form-ditto-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(1.0, forKey: "growthDifficulty")
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let date = now
        let s = CompanionStore(provider: FormTestProvider(), clock: { date }, fileURL: url, rng: SeededRNG(seed: 7),
                               defaults: defaults)
        XCTAssertEqual(s.currentForm, sandy)
        s.update(todayTokensByProvider: ["test": 0], todayDate: "d1", monthTotal: 0, burnTier: .idle,
                 limitWarning: false, hasUsageData: true)
        for _ in 0..<200 where !(s.state.active?.dittoRevealed ?? false) { await Task.yield() }
        XCTAssertEqual(s.state.active?.baseID, PokemonOdds.dittoSpeciesID)
        XCTAssertNil(s.state.active?.form)
        XCTAssertNil(s.currentForm)
    }

    // MARK: Names

    func testFormNamesComeFromFormNamesOfPokemonForm() async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "names": [["name": "Shaymin Céleste", "language": ["name": "fr"]]],
            "form_names": [["name": "Forme Céleste", "language": ["name": "fr"]],
                           ["name": "Sky Forme", "language": ["name": "en"]]],
        ])
        let server = FormNameServer(body)
        let client = PokemonNameClient(directory: nil, fetch: { try await server.fetch($0) })
        let resource = try XCTUnwrap(PokemonForm.nameResource(speciesID: 492, form: sky))
        let names = try await client.names(for: resource)
        XCTAssertEqual(names, ["fr": "Forme Céleste", "en": "Sky Forme"])
        let urls = await server.urls
        XCTAssertEqual(urls.map(\.absoluteString), ["https://pokeapi.co/api/v2/pokemon-form/10064/"])
        XCTAssertNil(PokemonForm.nameResource(speciesID: 201, form: .b), "Unown shows its letter")
        XCTAssertNil(PokemonForm.nameResource(speciesID: 25, form: nil))
        XCTAssertEqual(PokemonForm.nameResources(speciesID: 492).map(\.name), ["492", "10064"])
        XCTAssertEqual(PokemonForm.nameResources(speciesID: 201), [])
        XCTAssertEqual(PokemonForm.nameResources(speciesID: 479).map(\.name),
                       ["10058", "10059", "10060", "10061", "10062"], "Rotom's usual look has no official name")
    }

    func testUnnamedUsualLooksUseLocalizedNormalForm() {
        let names = PokemonNameDisplayStore()
        for id in [351, 479, 646, 649] {
            XCTAssertEqual(PokemonForm.label(speciesID: id, form: nil, language: .fr, names: names), "Forme Normale")
        }
        XCTAssertEqual(PokemonForm.label(speciesID: 479, form: PokemonForm("normal"), language: .de, names: names),
                       "Normalform")
        XCTAssertEqual(PokemonForm.label(speciesID: 479, form: PokemonForm("heat"), language: .fr, names: names),
                       "Heat", "Named forms keep the PokéAPI name")
        XCTAssertEqual(PokemonForm.displayName("Motisma", speciesID: 479, form: nil, language: .fr), "Motisma")
    }

    func testDisplayNameShowsOnlyNonDefaultFormsExceptUnown() async {
        let names = PokemonNameDisplayStore()
        let skyName = PokemonForm.nameResource(speciesID: 492, form: sky)!
        XCTAssertEqual(PokemonForm.label(speciesID: 492, form: sky, language: .fr, names: names), "Sky",
                       "Identifier until PokéAPI answers")
        _ = await names.load(skyName, provider: FixedNames(names: ["fr": "Forme Céleste", "en": "Sky Forme"]))
        XCTAssertEqual(PokemonForm.label(speciesID: 492, form: sky, language: .fr, names: names), "Forme Céleste")
        XCTAssertEqual(PokemonForm.label(speciesID: 201, form: .question, language: .fr, names: names), "?")
        XCTAssertNil(PokemonForm.label(speciesID: 25, form: sky, language: .fr, names: names))

        XCTAssertEqual(PokemonForm.displayName("Shaymin", speciesID: 492, form: sky, label: "Forme Céleste"),
                       "Shaymin [Forme Céleste]")
        XCTAssertEqual(PokemonForm.displayName("Shaymin", speciesID: 492, form: land, label: "Forme Terrestre"),
                       "Shaymin")
        XCTAssertEqual(PokemonForm.displayName("Zarbi", speciesID: 201, form: .a, label: nil), "Zarbi [A]")
        XCTAssertEqual(PokemonForm.displayName("Pikachu", speciesID: 25, form: sky, label: "Sky"), "Pikachu")
    }

    func testFormPickerKeepsSevenColumnsForUnownAndWidensNamedForms() {
        XCTAssertEqual(PokemonDetailView.formPickerColumns(formCount: 28), 7)
        XCTAssertEqual(PokemonDetailView.formPickerColumns(formCount: 18), 6)
        XCTAssertEqual(PokemonDetailView.formPickerColumns(formCount: 6), 4)
        XCTAssertEqual(PokemonDetailView.formPickerColumns(formCount: 2), 2)
    }
}
