import CryptoKit
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
    case downloadFailed(String)
    case rejected(String)
}

/// The Pokémon Showdown simulator as published on npm (`@pkmn/sim`, MIT, and what it loads).
///
/// Nothing of it ships in the repository or the app: like species data and sprites from PokéAPI, it
/// is fetched at runtime from its public source and cached on the user's device. Because this is
/// code, every archive is pinned to the exact SHA-512 npm publishes for it; a mismatch is refused.
enum BattleEnginePackages {
    struct Package: Sendable {
        let name: String
        let version: String
        /// npm `dist.integrity` without the `sha512-` prefix.
        let sha512: String

        var url: URL {
            let file = name.split(separator: "/").last.map(String.init) ?? name
            return URL(string: "https://registry.npmjs.org/\(name)/-/\(file)-\(version).tgz")!
        }
    }

    static let all = [
        Package(name: "@pkmn/sim", version: "0.11.0",
                sha512: "UH0b+9pUlqynCsBLpd8JE6sDINeMoKV/kbxFP7csAp11SqL3he+BAUTMGZbIc5fcbFSMUEaNMCboXe0yNI/rjw=="),
        Package(name: "@pkmn/sets", version: "6.0.0",
                sha512: "WhrKcJsH4hRpQIy52G1NYbSHTPHa3bLSWLL6vK9QSQeki8ugZ+M2yJScYl3GIFW8F1VxjzgJzWXvNXkoYCPTwA=="),
        Package(name: "@pkmn/streams", version: "1.1.0",
                sha512: "Pp9k7gt4xd76DqTU+LQEUyzuaauM4bV1MlehVtX1NS7o9zMFtjw50MfaEQ62dIMZyzxNjsJGoLGBeY1iSYLsRA=="),
        Package(name: "ts-chacha20", version: "1.2.0",
                sha512: "PTyPoWYHc2we8P2NTn5hpYG211popWbkjiw+k63xqjeMrx9pPtXSclz9F3fu0Tpr+vfR1xxcQFwsEkh1cXMLqw=="),
        Package(name: "@pkmn/protocol", version: "0.7.3",
                sha512: "ohSQhckON0OWf/0rlO3gioiR0pFdI/0YNh4lUtsFyrJ2ntrpdsF/n3tasFo2Mxag0fuWNsIGo9lwCFNbxSdi1A=="),
        Package(name: "@pkmn/view", version: "0.7.3",
                sha512: "dxCTOznJ75l7CZDkGVyk6lNF4yL6Z5O5YIPA0TmeOaVeWfM9jEYQgtsP7bxrYXPJztPVYckGJkS2Q+1reSCujA=="),
    ]

    /// `<state dir>/battle-engine-v1`, laid out like `node_modules`.
    static var defaultDirectory: URL {
        AppStatePaths.directory().appendingPathComponent("battle-engine-v1", isDirectory: true)
    }

    private static func marker(_ package: Package, in directory: URL) -> URL {
        directory.appendingPathComponent(package.name).appendingPathComponent(".installed-\(package.version)")
    }

    static func isInstalled(in directory: URL) -> Bool {
        all.allSatisfy { FileManager.default.fileExists(atPath: marker($0, in: directory).path) }
    }

    /// Downloads and unpacks whatever is missing. Safe to call every time a battle is prepared.
    static func install(into directory: URL, session: URLSession = .shared) async throws {
        for package in all where !FileManager.default.fileExists(atPath: marker(package, in: directory).path) {
            let (archive, response) = try await session.data(from: package.url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw BattleEngineError.downloadFailed("\(package.name): http")
            }
            guard verifies(archive, sha512: package.sha512) else {
                throw BattleEngineError.downloadFailed("\(package.name): hash mismatch")
            }
            try await unpack(archive, package: package, into: directory)
        }
    }

    static func verifies(_ archive: Data, sha512: String) -> Bool {
        Data(SHA512.hash(data: archive)).base64EncodedString() == sha512
    }

    private static func unpack(_ archive: Data, package: Package, into directory: URL) async throws {
        let fileManager = FileManager.default
        let destination = directory.appendingPathComponent(package.name, isDirectory: true)
        try? fileManager.removeItem(at: destination)   // a half-unpacked earlier attempt
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        let tarball = directory.appendingPathComponent("\(UUID().uuidString).tgz")
        try archive.write(to: tarball)
        defer { try? fileManager.removeItem(at: tarball) }

        // npm archives hold everything under `package/`. Skip what the loader never reads
        // (ES-module twins, source maps, typings): @pkmn/sim shrinks from 46 MB to about 20 MB.
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-xzf", tarball.path, "-C", destination.path, "--strip-components", "1",
                         "--exclude", "*.map", "--exclude", "*.mjs", "--exclude", "*.d.ts",
                         "--exclude", "*.d.mts", "--exclude", "package/build/esm"]
        tar.standardOutput = FileHandle.nullDevice
        tar.standardError = FileHandle.nullDevice
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            tar.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do { try tar.run() } catch { continuation.resume(throwing: error) }
        }
        guard status == 0 else { throw BattleEngineError.downloadFailed("\(package.name): unpack") }
        try Data().write(to: marker(package, in: directory))
    }
}

/// The simulator running in JavaScriptCore, driven through `battle-bridge.js`.
/// Only the host of a battle owns one; it is the single source of truth.
@MainActor
final class BattleEngine {
    enum SideID: String, Sendable { case p1, p2 }

    private let bridge: JSValue

    /// `directory` must already hold the packages (`BattleEnginePackages.install`).
    init(directory: URL = BattleEnginePackages.defaultDirectory) throws {
        // The packaged app carries the bridge in Contents/Resources; `swift run`/`swift test` find it
        // in SwiftPM's resource bundle. `Bundle.module` traps when absent, so it is only the fallback.
        guard BattleEnginePackages.isInstalled(in: directory),
              let url = Bundle.main.url(forResource: "battle-bridge", withExtension: "js")
                ?? Bundle.module.url(forResource: "battle-bridge", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8),
              let context = JSContext() else { throw BattleEngineError.scriptMissing }

        // The script's only window to the outside: read a text file below `directory`.
        let root = directory.standardizedFileURL.path
        let read: @convention(block) (String) -> Any = { path in
            let file = URL(fileURLWithPath: root).appendingPathComponent(path).standardizedFileURL.path
            guard file.hasPrefix(root + "/"),
                  let text = try? String(contentsOfFile: file, encoding: .utf8) else { return NSNull() }
            return text
        }
        context.setObject(read, forKeyedSubscript: "__read" as NSString)
        context.evaluateScript(source, withSourceURL: url)
        guard context.exception == nil,
              let bridge = context.objectForKeyedSubscript("PTBBattle"), bridge.isObject else {
            AppLog.write("battle engine failed to load: \(context.exception?.toString() ?? "no bridge")")
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
