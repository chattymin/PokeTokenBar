import XCTest
@testable import PokeTokenBar

private let psychicJSON = #"""
{"name":"psychic","power":90,"accuracy":100,"pp":10,"priority":0,
 "type":{"name":"psychic","url":""},"damage_class":{"name":"special","url":""},
 "target":{"name":"selected-pokemon","url":""},
 "stat_changes":[{"change":-1,"stat":{"name":"special-defense","url":""}}],
 "meta":{"ailment":{"name":"none","url":""},"category":{"name":"damage-lower","url":""},
         "min_hits":null,"max_hits":null,"drain":0,"healing":0,"crit_rate":0,
         "ailment_chance":0,"flinch_chance":0,"stat_chance":10}}
"""#

private func moveJSON(name: String, power: String = "40", damageClass: String = "physical") -> Data {
    Data(#"""
    {"name":"\#(name)","power":\#(power),"accuracy":100,"pp":35,"priority":0,
     "type":{"name":"normal"},"damage_class":{"name":"\#(damageClass)"},
     "target":{"name":"selected-pokemon"},"stat_changes":[],"meta":null}
    """#.utf8)
}

private func decodeMove(_ data: Data) throws -> BattleMove? {
    BattleMove(dto: try JSONDecoder().decode(BattleMoveDTO.self, from: data))
}

private func move(_ name: String, type: String = "normal", power: Int? = 40,
                  damageClass: BattleDamageClass = .physical) -> BattleMove {
    BattleMove(name: name, type: type, power: power, accuracy: 100, pp: 35, priority: 0,
               damageClass: damageClass, target: "selected-pokemon")
}

private let pikachuDetails = PokemonDetails(
    speciesID: 25, name: "pikachu", height: 4, weight: 60, baseExperience: 112, genderRate: 4,
    types: ["electric"],
    baseStats: ["hp": 35, "attack": 55, "defense": 40, "special-attack": 50, "special-defense": 50, "speed": 90],
    abilities: [PokemonAbilityOption(name: "static", slot: 1, isHidden: false)],
    moves: [])

private func entry(id: String = "entry", instanceID: String = "mon", speciesID: Int = 25, level: Int = 73,
                   moves: [String] = ["thunder-shock", "hidden-power"],
                   ivs: PokemonIVs = PokemonIVs(hp: 30, attack: 31, defense: 31,
                                                specialAttack: 30, specialDefense: 31, speed: 31)) -> DexEntry {
    var profile = PokemonProfile.generate(seed: 9, instanceID: instanceID)
    profile.level = level
    profile.ivs = ivs
    profile.abilityName = "static"
    profile.moves = moves.map { PokemonKnownMove(name: $0, learnedAtLevel: 1) }
    return DexEntry(id: id, baseID: 172, finalID: speciesID, chainOrder: [172, speciesID], rarity: .common,
                    caughtAt: nil, isShiny: true, nature: .modest, profile: profile,
                    names: [speciesID: ["en": "Pikachu", "ja-hrkt": "ピカチュウ"]])
}

private actor MoveServer {
    private(set) var calls: [String] = []
    var fails = false
    func setFailure(_ value: Bool) { fails = value }
    func fetch(_ url: URL) async throws -> Data {
        let name = url.lastPathComponent
        calls.append(name)
        try await Task.sleep(nanoseconds: 20_000_000)
        if fails { throw URLError(.notConnectedToInternet) }
        return name == "wrong-name" ? moveJSON(name: "tackle") : moveJSON(name: name)
    }
}

private struct StubDetails: PokemonDetailProviding {
    let details: [Int: PokemonDetails]
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails {
        guard let value = details[speciesID] else { throw URLError(.fileDoesNotExist) }
        return value
    }
}

private actor StubMoves: BattleMoveProviding {
    private(set) var requested: [String] = []
    func move(named name: String) async throws -> BattleMove {
        requested.append(name)
        return BattleMove(name: name, type: "normal", power: 40, accuracy: 100, pp: 35, priority: 0,
                          damageClass: .physical, target: "selected-pokemon")
    }
}

final class BattleMoveTests: XCTestCase {
    private func tempDirectory() throws -> URL {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("BattleMoves-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        return path
    }

    func testDecodesDamageMoveWithSecondaryStatDrop() throws {
        let move = try XCTUnwrap(try decodeMove(Data(psychicJSON.utf8)))
        XCTAssertEqual(move.name, "psychic")
        XCTAssertEqual(move.type, "psychic")
        XCTAssertEqual(move.power, 90)
        XCTAssertEqual(move.damageClass, .special)
        XCTAssertEqual(move.statChanges, [BattleStatChange(stat: "special-defense", change: -1)])
        XCTAssertEqual(move.category, "damage-lower")
        XCTAssertEqual(move.statChance, 10)
        XCTAssertTrue(move.isDamaging)
    }

    func testStatusMoveWithoutPowerIsNotDamaging() throws {
        let growl = try XCTUnwrap(try decodeMove(moveJSON(name: "growl", power: "null", damageClass: "status")))
        XCTAssertNil(growl.power)
        XCTAssertFalse(growl.isDamaging)
        let seismicToss = try XCTUnwrap(try decodeMove(moveJSON(name: "seismic-toss", power: "null")))
        XCTAssertFalse(seismicToss.isDamaging, "Fixed-damage moves have no power and need their own engine rule")
    }

    func testServerValuesAreClampedAndMissingMetaDefaults() throws {
        let data = Data(#"""
        {"name":"broken","power":999,"accuracy":0,"pp":null,"priority":20,
         "type":{"name":"normal"},"damage_class":{"name":"physical"},"target":{"name":"user"},
         "stat_changes":[{"change":12,"stat":{"name":"speed"}},{"change":-9,"stat":{"name":"attack"}}],
         "meta":{"ailment":null,"category":null,"min_hits":0,"max_hits":99,"drain":500,"healing":-500,
                 "crit_rate":40,"ailment_chance":150,"flinch_chance":-3,"stat_chance":101}}
        """#.utf8)
        let move = try XCTUnwrap(try decodeMove(data))
        XCTAssertEqual(move.power, 250)
        XCTAssertEqual(move.accuracy, 1)
        XCTAssertEqual(move.pp, 1)
        XCTAssertEqual(move.priority, 5)
        XCTAssertEqual(move.statChanges, [BattleStatChange(stat: "attack", change: -6),
                                          BattleStatChange(stat: "speed", change: 6)])
        XCTAssertEqual(move.minHits, 1)
        XCTAssertEqual(move.maxHits, 10)
        XCTAssertEqual(move.drain, 100)
        XCTAssertEqual(move.healing, -100)
        XCTAssertEqual(move.critRate, 6)
        XCTAssertEqual(move.ailmentChance, 100)
        XCTAssertEqual(move.flinchChance, 0)
        XCTAssertEqual(move.statChance, 100)

        let bare = try XCTUnwrap(try decodeMove(moveJSON(name: "tackle")))
        XCTAssertEqual(bare.statChance, 0)
        XCTAssertNil(bare.category)
    }

    func testUnknownOrMissingDamageClassIsRejected() throws {
        XCTAssertNil(try decodeMove(moveJSON(name: "future", damageClass: "psionic")))
        let missing = Data(#"""
        {"name":"future","power":40,"accuracy":100,"pp":5,"priority":0,"type":{"name":"normal"},
         "damage_class":null,"target":{"name":"user"},"stat_changes":[],"meta":null}
        """#.utf8)
        XCTAssertNil(try decodeMove(missing))
    }

    func testMemoryAndDiskCacheShareOneFetch() async throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let server = MoveServer()
        let client = BattleMoveClient(directory: directory, fetch: { try await server.fetch($0) })
        let first = try await client.move(named: "tackle")
        let second = try await client.move(named: "tackle")
        let restored = BattleMoveClient(directory: directory, fetch: { try await server.fetch($0) })
        let disk = try await restored.move(named: "tackle")
        XCTAssertEqual(first, second)
        XCTAssertEqual(first, disk)
        let calls = await server.calls
        XCTAssertEqual(calls, ["tackle"])
    }

    func testConcurrentRequestsShareOneFetch() async throws {
        let server = MoveServer()
        let client = BattleMoveClient(directory: nil, fetch: { try await server.fetch($0) })
        async let a = client.move(named: "tackle")
        async let b = client.move(named: "tackle")
        let values = try await (a, b)
        XCTAssertEqual(values.0, values.1)
        let calls = await server.calls
        XCTAssertEqual(calls.count, 1)
    }

    func testExpiredDiskSurvivesOfflineAndRefetchesOnceOnline() async throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let time = Date(timeIntervalSince1970: 1_800_000_000)
        let server = MoveServer()
        _ = try await BattleMoveClient(directory: directory, now: { time }, fetch: { try await server.fetch($0) })
            .move(named: "tackle")
        await server.setFailure(true)
        let later = BattleMoveClient(directory: directory, now: { time.addingTimeInterval(31 * 86400) },
                                     fetch: { try await server.fetch($0) })
        let offline = try await later.move(named: "tackle")
        XCTAssertEqual(offline.name, "tackle")
        await server.setFailure(false)
        _ = try await later.move(named: "tackle")
        let calls = await server.calls
        XCTAssertEqual(calls.count, 3, "Offline fallback keeps the old timestamp so it refetches once online")
    }

    func testColdOfflineFailureThrows() async {
        let server = MoveServer()
        await server.setFailure(true)
        let client = BattleMoveClient(directory: nil, fetch: { try await server.fetch($0) })
        do {
            _ = try await client.move(named: "tackle")
            XCTFail("expected failure without any cache")
        } catch {}
    }

    func testInvalidNameNeverFetchesAndMismatchedResponseIsRejected() async throws {
        let server = MoveServer()
        let client = BattleMoveClient(directory: nil, fetch: { try await server.fetch($0) })
        for name in ["../pokemon/1", "Tackle", ""] {
            do {
                _ = try await client.move(named: name)
                XCTFail("\(name) must be rejected")
            } catch {}
        }
        var calls = await server.calls
        XCTAssertTrue(calls.isEmpty)
        do {
            _ = try await client.move(named: "wrong-name")
            XCTFail("a response for another move must not be cached under this name")
        } catch {}
        calls = await server.calls
        XCTAssertEqual(calls, ["wrong-name"])
    }
}

final class BattleSnapshotTests: XCTestCase {
    private let moves = ["thunder-shock": move("thunder-shock", type: "electric", damageClass: .special),
                         "hidden-power": move("hidden-power", power: 60, damageClass: .special)]

    func testSnapshotKeepsRealLevelAndResolvesStatsMovesAndIdentity() throws {
        let source = entry()
        let pokemon = try BattleSnapshotBuilder.pokemon(from: source, details: pikachuDetails, moves: moves)
        let expected = PokemonStatCalculator.stats(details: pikachuDetails, profile: source.profile!, nature: .modest)
        let value = { (name: String) in expected.first { $0.name == name }!.value }

        XCTAssertEqual(pokemon.level, 73, "Battles use the raised level, not a normalized one")
        XCTAssertEqual(pokemon.stats, BattleStats(
            hp: value("hp"), attack: value("attack"), defense: value("defense"),
            specialAttack: value("special-attack"), specialDefense: value("special-defense"),
            speed: value("speed")))
        XCTAssertEqual(pokemon.instanceID, "mon")
        XCTAssertEqual(pokemon.speciesID, 25)
        XCTAssertEqual(pokemon.types, ["electric"])
        XCTAssertEqual(pokemon.names["ja-hrkt"], "ピカチュウ")
        XCTAssertTrue(pokemon.isShiny)
        XCTAssertEqual(pokemon.nature, .modest)
        XCTAssertEqual(pokemon.abilityName, "static")
        XCTAssertEqual(pokemon.moves.map(\.name), ["thunder-shock", "hidden-power"])
        XCTAssertEqual(pokemon.moves[0].type, "electric")
        XCTAssertEqual(pokemon.moves[1].type, "grass", "Hidden Power takes its type from the IVs")
    }

    func testHiddenPowerTypeFollowsKnownIVSpreads() {
        func type(_ hp: Int, _ atk: Int, _ def: Int, _ spa: Int, _ spd: Int, _ spe: Int) -> String {
            HiddenPower.type(for: PokemonIVs(hp: hp, attack: atk, defense: def,
                                             specialAttack: spa, specialDefense: spd, speed: spe))
        }
        XCTAssertEqual(type(31, 31, 31, 31, 31, 31), "dark")
        XCTAssertEqual(type(0, 0, 0, 0, 0, 0), "fighting")
        XCTAssertEqual(type(30, 31, 31, 30, 31, 31), "grass")
        XCTAssertEqual(type(31, 30, 30, 31, 31, 31), "ice")
        XCTAssertEqual(type(31, 30, 31, 30, 31, 30), "fire")
    }

    func testBuilderRejectsIncompleteEntries() {
        var noProfile = entry()
        noProfile.profile = nil
        XCTAssertThrowsError(try BattleSnapshotBuilder.pokemon(from: noProfile, details: pikachuDetails, moves: moves)) {
            XCTAssertEqual($0 as? BattleSnapshotError, .missingProfile(entryID: "entry"))
        }
        XCTAssertThrowsError(try BattleSnapshotBuilder.pokemon(from: entry(moves: []), details: pikachuDetails, moves: moves)) {
            XCTAssertEqual($0 as? BattleSnapshotError, .notEnriched(entryID: "entry"))
        }
        XCTAssertThrowsError(try BattleSnapshotBuilder.pokemon(from: entry(moves: ["surf"]), details: pikachuDetails, moves: moves)) {
            XCTAssertEqual($0 as? BattleSnapshotError, .missingMove(entryID: "entry", move: "surf"))
        }
        var noSpeed = pikachuDetails.baseStats
        noSpeed["speed"] = nil
        let broken = PokemonDetails(speciesID: 25, name: "pikachu", height: 4, weight: 60, baseExperience: nil,
                                    genderRate: 4, types: ["electric"], baseStats: noSpeed, abilities: [], moves: [])
        XCTAssertThrowsError(try BattleSnapshotBuilder.pokemon(from: entry(), details: broken, moves: moves)) {
            XCTAssertEqual($0 as? BattleSnapshotError, .incompleteStats(entryID: "entry"))
        }
    }

    func testTeamAllowsOneToSixUniqueIndividuals() throws {
        let members = try (0..<7).map {
            try BattleSnapshotBuilder.pokemon(from: entry(instanceID: "mon-\($0)"), details: pikachuDetails, moves: moves)
        }
        XCTAssertEqual(try BattleTeam(members: Array(members.prefix(1))).members.count, 1)
        XCTAssertEqual(try BattleTeam(members: Array(members.prefix(6))).members.count, 6)
        XCTAssertThrowsError(try BattleTeam(members: [])) {
            XCTAssertEqual($0 as? BattleSnapshotError, .invalidTeamSize(0))
        }
        XCTAssertThrowsError(try BattleTeam(members: members)) {
            XCTAssertEqual($0 as? BattleSnapshotError, .invalidTeamSize(7))
        }
        XCTAssertThrowsError(try BattleTeam(members: [members[0], members[1], members[0]])) {
            XCTAssertEqual($0 as? BattleSnapshotError, .duplicateMember("mon-0"))
        }
    }

    func testTeamSurvivesCodableRoundTrip() throws {
        let team = try BattleTeam(members: [
            try BattleSnapshotBuilder.pokemon(from: entry(), details: pikachuDetails, moves: moves)])
        let decoded = try JSONDecoder().decode(BattleTeam.self, from: try JSONEncoder().encode(team))
        XCTAssertEqual(decoded, team)
    }

    func testLoaderFetchesEachMoveOnceAndKeepsPickedOrder() async throws {
        let stubMoves = StubMoves()
        let loader = BattleTeamLoader(details: StubDetails(details: [25: pikachuDetails]), moves: stubMoves)
        let team = try await loader.load([
            entry(id: "b", instanceID: "second", moves: ["tackle", "growl"]),
            entry(id: "a", instanceID: "first", moves: ["growl", "quick-attack"]),
        ])
        XCTAssertEqual(team.members.map(\.instanceID), ["second", "first"])
        XCTAssertEqual(team.members[1].moves.map(\.name), ["growl", "quick-attack"])
        let requested = await stubMoves.requested
        XCTAssertEqual(requested.sorted(), ["growl", "quick-attack", "tackle"])
    }

    func testLoaderPropagatesMissingDetails() async {
        let loader = BattleTeamLoader(details: StubDetails(details: [:]), moves: StubMoves())
        do {
            _ = try await loader.load([entry()])
            XCTFail("expected details failure")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .fileDoesNotExist)
        }
    }
}
