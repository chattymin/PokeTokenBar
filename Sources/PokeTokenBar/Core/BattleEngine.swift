import Foundation
import JavaScriptCore

/// One Pokémon as it enters a battle. This is also the wire format a challenger sends, so the
/// receiving side treats every field as untrusted — the JS bridge clamps and validates all of it.
struct BattleTeamMember: Codable, Sendable, Equatable {
    var dex: Int
    var name: String
    var level: Int
    var gender: String          // "M" / "F" / "N" / "" (unknown → the simulator rolls one)
    var shiny: Bool
    var nature: String
    var ability: String
    var moves: [String]
    var ivs: [String: Int]      // Showdown stat ids: hp atk def spa spd spe
    /// `PokemonForm.rawValue` — cosmetic only, echoed back in snapshots to pick the sprite.
    var sprite: String

    init(entry: DexEntry, name: String) {
        let profile = entry.profile
        dex = entry.finalID
        self.name = name
        level = profile?.level ?? 5
        switch profile?.gender {
        case .male: gender = "M"
        case .female: gender = "F"
        case .genderless: gender = "N"
        case nil: gender = ""
        }
        shiny = entry.isShiny
        nature = entry.nature?.rawValue ?? ""
        ability = profile?.abilityName ?? ""
        moves = profile?.moves.map(\.name) ?? []
        let iv = profile?.ivs
        ivs = ["hp": iv?.hp ?? 0, "atk": iv?.attack ?? 0, "def": iv?.defense ?? 0,
               "spa": iv?.specialAttack ?? 0, "spd": iv?.specialDefense ?? 0, "spe": iv?.speed ?? 0]
        sprite = PokemonForm.resolved(speciesID: entry.finalID, form: entry.form)?.rawValue ?? ""
    }
}

struct BattlePlayer: Codable, Sendable, Equatable {
    var name: String
    var team: [BattleTeamMember]
}

/// What one side is allowed to see after the simulator advanced. Produced by `entry.js`.
struct BattleSnapshot: Codable, Sendable, Equatable {
    struct Mon: Codable, Sendable, Equatable, Identifiable {
        var id: String { "\(dex)-\(name)-\(level)" }
        var name: String
        var species: String
        var dex: Int
        var sprite: String
        var shiny: Bool
        var level: Int
        /// Exact for the viewer's own team; a 0...100 percentage for the opponent.
        var hp: Int
        var maxhp: Int
        var status: String
        var fainted: Bool
        var active: Bool

        var form: PokemonForm? {
            PokemonForm.resolved(speciesID: dex, form: sprite.isEmpty ? nil : PokemonForm(sprite))
        }
    }

    struct Side: Codable, Sendable, Equatable {
        var name: String
        var team: [Mon]
        /// Opponent only: Pokémon still able to fight, including ones not yet revealed.
        var left: Int?
        var active: Mon? { team.first(where: \.active) }
    }

    struct Move: Codable, Sendable, Equatable, Identifiable {
        var id: Int { slot }
        var slot: Int
        var name: String
        var type: String
        var pp: Int
        var maxpp: Int
        var disabled: Bool
    }

    struct Request: Codable, Sendable, Equatable {
        /// "move" (pick a move or switch), "switch" (forced replacement) or "wait".
        var kind: String
        var moves: [Move]?
        /// 1-based team slots that may switch in.
        var switches: [Int]?
    }

    var turn: Int
    var ended: Bool
    /// "" while running, then "me" / "foe" / "tie".
    var winner: String
    /// New log lines since the previous snapshot, already phrased for this viewer.
    var log: [String]
    var me: Side
    var foe: Side
    var request: Request
}

enum BattleEngineError: Error, Equatable {
    case scriptMissing
    case rejected(String)
}

/// The Pokémon Showdown simulator (bundled as `showdown-battle.js`, see `scripts/battle-engine`)
/// running in JavaScriptCore. Only the host of a battle owns one; it is the single source of truth.
@MainActor
final class BattleEngine {
    enum SideID: String, Sendable { case p1, p2 }

    private let bridge: JSValue

    init() throws {
        // The packaged app carries the script in Contents/Resources; `swift run`/`swift test` find it
        // in SwiftPM's resource bundle. `Bundle.module` traps when absent, so it is only the fallback.
        guard let url = Bundle.main.url(forResource: "showdown-battle", withExtension: "js")
                ?? Bundle.module.url(forResource: "showdown-battle", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8),
              let context = JSContext() else { throw BattleEngineError.scriptMissing }
        context.evaluateScript(source, withSourceURL: url)
        guard let bridge = context.objectForKeyedSubscript("PTBBattle"), bridge.isObject else {
            throw BattleEngineError.scriptMissing
        }
        self.bridge = bridge
    }

    func start(host: BattlePlayer, guest: BattlePlayer) throws -> [SideID: BattleSnapshot] {
        let players = try JSONEncoder().encode(["p1": host, "p2": guest])
        return try call("start", [String(decoding: players, as: UTF8.self)])
    }

    /// `choice` is "move N" or "switch N". An illegal choice throws `.rejected` and changes nothing.
    func choose(_ side: SideID, _ choice: String) throws -> [SideID: BattleSnapshot] {
        try call("choose", [side.rawValue, choice])
    }

    func forfeit(_ side: SideID) throws -> [SideID: BattleSnapshot] {
        try call("forfeit", [side.rawValue])
    }

    private struct Reply: Decodable {
        var error: String?
        var p1: BattleSnapshot?
        var p2: BattleSnapshot?
    }

    private func call(_ method: String, _ arguments: [Any]) throws -> [SideID: BattleSnapshot] {
        let context = bridge.context
        context?.exception = nil
        let result = bridge.invokeMethod(method, withArguments: arguments)
        if let exception = context?.exception {
            context?.exception = nil
            throw BattleEngineError.rejected(exception.toString() ?? "error")
        }
        guard let json = result?.toString(),
              let reply = try? JSONDecoder().decode(Reply.self, from: Data(json.utf8)) else {
            throw BattleEngineError.rejected("bad reply")
        }
        if let error = reply.error { throw BattleEngineError.rejected(error) }
        guard let p1 = reply.p1, let p2 = reply.p2 else { throw BattleEngineError.rejected("bad reply") }
        return [.p1: p1, .p2: p2]
    }
}
