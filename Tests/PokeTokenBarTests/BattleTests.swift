import AppKit
import Network
import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor
final class BattleTests: XCTestCase {
    /// Only VPN (point-to-point) subnets are searched, as a /24 without our own address.
    func testVPNSearchCoversOnlyPointToPointSubnets() {
        defer { BattleSession.localAddresses = BattleSession.interfaceAddresses }
        BattleSession.localAddresses = { [("192.168.1.20", false), ("10.8.0.2", true)] }
        let hosts = BattleSession.vpnHosts()
        XCTAssertEqual(hosts.count, 253)
        XCTAssertEqual([hosts.first, hosts.last], ["10.8.0.1", "10.8.0.254"])
        XCTAssertFalse(hosts.contains("10.8.0.2"))
        BattleSession.localAddresses = { [("192.168.1.20", false)] }
        XCTAssertTrue(BattleSession.vpnHosts().isEmpty)
        XCTAssertTrue(BattleSession.interfaceAddresses().allSatisfy { !$0.ip.hasPrefix("127.") })
    }

    private func member(_ dex: Int, level: Int, moves: [String], name: String? = nil) -> BattleTeamMember {
        var profile = PokemonProfile.generate(seed: UInt64(dex))
        profile.level = level
        profile.gender = .male
        profile.moves = moves.map { PokemonKnownMove(name: $0, learnedAtLevel: 1) }
        let entry = DexEntry(baseID: dex, finalID: dex, chainOrder: [dex], rarity: .common, caughtAt: nil,
                             nature: .adamant, profile: profile)
        return BattleTeamMember(entry: entry, name: name ?? "Mon\(dex)")
    }

    private var ash: BattlePlayer {
        BattlePlayer(name: "Ash", team: [member(3, level: 50, moves: ["vine-whip", "tackle"]),
                                         member(25, level: 30, moves: ["thunder-shock"])])
    }
    private var gary: BattlePlayer {
        BattlePlayer(name: "Gary", team: [member(9, level: 50, moves: ["water-gun", "bite"]),
                                          member(143, level: 45, moves: ["body-slam"])])
    }

    /// The simulator is not in the repository: tests fetch the pinned npm packages once into a
    /// reused temp directory, and skip when the registry cannot be reached.
    private func engineDirectory() async throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ptb-battle-engine-tests")
        do {
            try await BattleEnginePackages.install(into: directory)
        } catch {
            throw XCTSkip("battle engine packages unavailable: \(error)")
        }
        return directory
    }

    private func sessions() async throws -> (host: BattleSession, guest: BattleSession) {
        let directory = try await engineDirectory()
        return (BattleSession(advertises: false, engineDirectory: directory),
                BattleSession(advertises: false, engineDirectory: directory))
    }

    func testPackagePinsRejectTamperedArchives() {
        let archive = Data("not the real tarball".utf8)
        XCTAssertFalse(BattleEnginePackages.verifies(archive, sha512: BattleEnginePackages.all[0].sha512))
        XCTAssertTrue(BattleEnginePackages.verifies(
            archive, sha512: "MRqvs50psUtGELoeBcJwDUi7lT6RUXBzTHsU3U701V/DIouBQSZo+tx5xSXDJLEcItepyZPjIncx8Xy4qPFlKw=="))
        XCTAssertEqual(BattleEnginePackages.all[0].url.absoluteString,
                       "https://registry.npmjs.org/@pkmn/sim/-/sim-0.11.0.tgz")
    }

    func testEngineRefusesToStartWithoutPackages() {
        let empty = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertThrowsError(try BattleEngine(directory: empty)) {
            XCTAssertEqual($0 as? BattleEngineError, .scriptMissing)
        }
    }

    private func firstChoice(_ request: BattleSnapshot.Request) -> String? {
        switch request.kind {
        case "move": return request.moves?.first { !$0.disabled }.map { "move \($0.slot)" }
        case "switch": return request.switches?.first.map { "switch \($0)" }
        default: return nil
        }
    }

    /// Each side reads the log and move descriptions in its own language; names stay English.
    func testEngineLocalizesTextPerSideAndDescribesMovesAndTypes() async throws {
        var host = ash, guest = gary
        host.lang = "ru"
        guest.lang = "en"
        let engine = try BattleEngine(directory: try await engineDirectory())
        var snapshots = try engine.start(host: host, guest: guest)
        var ru = try XCTUnwrap(snapshots[.p1]), en = try XCTUnwrap(snapshots[.p2])
        XCTAssertTrue(ru.log.contains("Вперёд, Mon3 (Venusaur)!"), "\(ru.log)")
        XCTAssertTrue(en.log.contains("Go! Mon9 (Blastoise)!"), "\(en.log)")

        // Venusaur (Grass/Poison) against Blastoise (Water).
        let vineWhip = try XCTUnwrap(ru.request.moves?.first)
        XCTAssertEqual([vineWhip.category, vineWhip.type], ["Physical", "Grass"])
        XCTAssertEqual([vineWhip.power, vineWhip.accuracy, vineWhip.priority], [35, 100, 0])
        XCTAssertEqual(vineWhip.effect, 2)
        XCTAssertEqual(vineWhip.desc, "Без дополнительного эффекта.")
        XCTAssertEqual(en.request.moves?.first?.desc, "No additional effect.")
        XCTAssertEqual(en.request.moves?.first?.effect, 0.5, "Water Gun into Grass")
        XCTAssertEqual(BattleView.facts(vineWhip, L(.ru)), "Травяной · Физическая · Сила 35 · Точность 100%")

        let venusaur = try XCTUnwrap(ru.me.active), blastoise = try XCTUnwrap(ru.foe.active)
        XCTAssertEqual(venusaur.types, ["Grass", "Poison"])
        XCTAssertEqual(venusaur.defense, ["Fire": 2, "Ice": 2, "Flying": 2, "Psychic": 2,
                                          "Water": 0.5, "Electric": 0.5, "Fighting": 0.5, "Grass": 0.25])
        XCTAssertEqual(venusaur.offense?["Poison"], ["Grass": 2, "Poison": 0.5, "Ground": 0.5, "Rock": 0.5,
                                                     "Ghost": 0.5, "Steel": 0])
        XCTAssertEqual(blastoise.defense, ["Electric": 2, "Grass": 2, "Fire": 0.5, "Water": 0.5, "Ice": 0.5, "Steel": 0.5])
        XCTAssertNil(ru.me.team.last?.defense, "only the Pokémon on the field carries matchups")
        XCTAssertEqual(ru.me.team.last?.types, ["Electric"], "the bench shows its types on the switch buttons")
        XCTAssertEqual([4, 0.5, 0.25, 0].map(BattleView.times), ["×4", "×½", "×¼", "×0"])
        for (type, style) in BattleView.typeStyles {
            XCTAssertNotEqual(L(.ru).battleType(type), type, "\(type) has a localized name")
            XCTAssertNotNil(NSImage(systemSymbolName: style.symbol, accessibilityDescription: nil), style.symbol)
        }
        XCTAssertEqual(BattleView.typeStyles.count, 17)

        _ = try engine.choose(.p1, "move 1")
        snapshots = try engine.choose(.p2, "move 1")
        ru = try XCTUnwrap(snapshots[.p1]); en = try XCTUnwrap(snapshots[.p2])
        XCTAssertTrue(ru.log.contains("Mon3 использует Vine Whip!"), "\(ru.log)")
        XCTAssertTrue(ru.log.contains("Это суперэффективно!"))
        XCTAssertTrue(ru.log.contains("Mon9 соперника использует Water Gun!"))
        XCTAssertTrue(en.log.contains("The opposing Mon3 used Vine Whip!"), "\(en.log)")
        XCTAssertTrue(en.log.contains("It's super effective!"))
    }

    func testEngineUsesProfileDataAndRealLevels() async throws {
        let snapshots = try BattleEngine(directory: try await engineDirectory()).start(host: ash, guest: gary)
        let p1 = try XCTUnwrap(snapshots[.p1]), p2 = try XCTUnwrap(snapshots[.p2])
        XCTAssertEqual(p1.me.team.map(\.level), [50, 30])
        XCTAssertEqual(p1.request.moves?.map(\.name), ["Vine Whip", "Tackle"])
        // The opponent is seen as a percentage and only once revealed.
        XCTAssertEqual(p1.foe.team.map(\.dex), [9])
        XCTAssertEqual(p1.foe.active?.maxhp, 100)
        XCTAssertEqual(p2.me.active?.dex, 9)
        XCTAssertEqual(p1.foe.left, 2)
    }

    func testEngineRejectsIllegalChoicesAndUnknownSpecies() async throws {
        let engine = try BattleEngine(directory: try await engineDirectory())
        _ = try engine.start(host: ash, guest: gary)
        XCTAssertThrowsError(try engine.choose(.p1, "move 4"))      // only two moves
        XCTAssertThrowsError(try engine.choose(.p1, "switch 1"))    // already active
        XCTAssertThrowsError(try engine.choose(.p1, "team 123"))    // not a battle choice
        XCTAssertNoThrow(try engine.choose(.p1, "move 1"))

        var bogus = gary
        bogus.team[0].dex = 99_999
        XCTAssertThrowsError(try engine.start(host: ash, guest: bogus))
    }

    func testEnginePlaysABattleToTheEnd() async throws {
        let engine = try BattleEngine(directory: try await engineDirectory())
        var snapshots = try engine.start(host: ash, guest: gary)
        for _ in 0..<400 where snapshots[.p1]?.ended == false {
            for side in [BattleEngine.SideID.p1, .p2] {
                guard let request = snapshots[side]?.request, let choice = firstChoice(request) else { continue }
                snapshots = try engine.choose(side, choice)
            }
        }
        let p1 = try XCTUnwrap(snapshots[.p1]), p2 = try XCTUnwrap(snapshots[.p2])
        XCTAssertTrue(p1.ended)
        XCTAssertEqual(Set([p1.winner, p2.winner]), ["me", "foe"])
    }

    /// Host and challenger over a real loopback TCP connection: challenge → accept → play to the end.
    func testTwoSessionsBattleOverLoopback() async throws {
        let (host, guest) = try await sessions()
        defer { host.stop(); guest.stop() }
        host.enterLobby(as: ash)
        guest.enterLobby(as: gary)
        try await wait { host.port != nil }
        let port = try XCTUnwrap(host.port)

        XCTAssertFalse(guest.challenge(address: " "))
        XCTAssertFalse(guest.challenge(address: "127.0.0.1:port"))
        XCTAssertFalse(guest.challenge(address: "127.0.0.1:"))

        // A VPN carries no Bonjour: the scan asks the address itself and lists whoever answers.
        guest.scan(hosts: ["127.0.0.1"], port: port)
        try await wait { guest.peers.count == 1 }
        XCTAssertEqual(guest.peers.first?.name, "\(ash.name) (127.0.0.1)")
        try await wait { !guest.scanning }
        XCTAssertEqual(host.phase, .lobby, "a probe is not a challenge")
        XCTAssertNil(host.notice)
        XCTAssertTrue(host.addresses.allSatisfy { $0.hasSuffix(":\(port.rawValue)") })
        XCTAssertTrue(guest.challenge(address: " 127.0.0.1:\(port.rawValue) "))
        try await wait { host.phase == .incoming("Gary") }
        host.accept()
        try await wait { guest.phase == .battle }
        XCTAssertEqual(guest.snapshot?.me.active?.dex, 9)
        XCTAssertEqual(host.snapshot?.me.active?.dex, 3)

        // Chat lands in both logs, in order, with its author; the wire copy is clipped.
        guest.say("  gl hf  ")
        host.say(String(repeating: "x", count: 500))
        try await wait { host.log.contains { $0.author == "Gary" } && guest.log.contains { $0.author == "Ash" } }
        XCTAssertEqual(host.log.first { $0.author == "Gary" }?.text, "gl hf")
        XCTAssertEqual(guest.log.first { $0.author == "Ash" }?.text.count, BattleSession.maxChatLength)
        XCTAssertEqual(guest.log.filter { $0.author == "Gary" }.count, 1, "the sender sees their own line once")

        for _ in 0..<400 where host.snapshot?.ended == false {
            let turnLog = host.log.count
            for session in [host, guest] {
                if let request = session.snapshot?.request, let choice = firstChoice(request) {
                    session.choose(choice)
                }
            }
            try await wait { host.log.count > turnLog && host.snapshot?.turn == guest.snapshot?.turn
                && host.snapshot?.ended == guest.snapshot?.ended }
        }
        XCTAssertEqual(host.snapshot?.ended, true)
        XCTAssertEqual(Set([host.snapshot?.winner, guest.snapshot?.winner]), ["me", "foe"])

        // The result stays readable after the other side leaves.
        guest.leaveBattle()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(host.phase, .battle)
        XCTAssertNil(host.notice)
    }

    func testDeclineAndMidBattleDisconnectReturnToLobby() async throws {
        let (host, guest) = try await sessions()
        defer { host.stop(); guest.stop() }
        host.enterLobby(as: ash)
        guest.enterLobby(as: gary)
        try await wait { host.port != nil }
        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: try XCTUnwrap(host.port))

        guest.challenge(endpoint: endpoint, name: "Ash")
        try await wait { host.phase == .incoming("Gary") }
        host.decline()
        try await wait { guest.phase == .lobby }
        XCTAssertEqual(guest.notice, .declined)

        guest.challenge(endpoint: endpoint, name: "Ash")
        try await wait { host.phase == .incoming("Gary") }
        host.accept()
        try await wait { guest.phase == .battle }
        guest.stop()
        try await wait { host.phase == .lobby }
        XCTAssertEqual(host.notice, .disconnected)
        XCTAssertNil(host.snapshot)
    }

    /// Opt-in: renders the battle window's three screens with sample data (used for PR images).
    func testRenderBattleScreens() async throws {
        guard let path = ProcessInfo.processInfo.environment["PTB_BATTLE_SCREENSHOT_DIR"] else {
            throw XCTSkip("set PTB_BATTLE_SCREENSHOT_DIR to render")
        }
        let output = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        var state = CompanionState()
        // PTB_BATTLE_SCREENSHOT_LANG=ru renders the localized log and move descriptions.
        let language = ProcessInfo.processInfo.environment["PTB_BATTLE_SCREENSHOT_LANG"].flatMap(AppLanguage.init) ?? .en
        state.language = language
        state.dex = [(3, "Venusaur", 50), (6, "Charizard", 47), (9, "Blastoise", 52), (25, "Pikachu", 30),
                     (143, "Snorlax", 45), (94, "Gengar", 41), (130, "Gyarados", 38), (149, "Dragonite", 61)]
            .map { id, name, level in
                var profile = PokemonProfile.generate(seed: UInt64(id))
                profile.level = level
                return DexEntry(baseID: id, finalID: id, chainOrder: [id], rarity: .common, caughtAt: Date(),
                                nature: .adamant, profile: profile, names: [id: ["en": name]])
            }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("battle-render-\(UUID().uuidString).json")
        try JSONEncoder().encode(state).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let store = CompanionStore(fileURL: file)

        let (host, guest) = try await sessions()
        defer { host.stop(); guest.stop() }
        try await render(BattleView(store: store, session: host, playerName: "Ash"), to: output, name: "team")

        BattleSession.localAddresses = { [("192.168.1.20", false), ("10.8.0.2", true)] }   // sample, not this Mac's
        defer { BattleSession.localAddresses = BattleSession.interfaceAddresses }
        let me = BattlePlayer(name: "Ash", team: [member(3, level: 50, moves: ["vine-whip", "sleep-powder", "sludge-bomb", "synthesis"], name: "Venusaur"),
                                                  member(25, level: 30, moves: ["thunder-shock"], name: "Pikachu")],
                              lang: language.rawValue)
        let rival = BattlePlayer(name: "Gary", team: [member(9, level: 50, moves: ["water-gun", "bite"], name: "Blastoise"),
                                                      member(143, level: 45, moves: ["body-slam"], name: "Snorlax")])
        host.enterLobby(as: me)
        guest.enterLobby(as: rival)
        try await wait { host.port != nil }
        try await render(BattleView(store: store, session: host, playerName: "Ash"), to: output, name: "lobby-address")
        guest.challenge(endpoint: .hostPort(host: "127.0.0.1", port: try XCTUnwrap(host.port)), name: "Ash")
        try await wait { host.phase == .incoming("Gary") }
        try await render(BattleView(store: store, session: host, playerName: "Ash"), to: output, name: "lobby")

        host.accept()
        try await wait { guest.phase == .battle }
        host.choose("move 1")
        guest.choose("move 1")
        try await wait { host.snapshot?.turn == 2 }
        guest.say("gl hf!")
        try await wait { host.log.contains { $0.author != nil } }
        let battle = BattleView(store: store, session: host, playerName: "Ash")
        try await render(battle, to: output, name: "battle")
        try await render(battle.typeChart(try XCTUnwrap(host.snapshot)), to: output, name: "types",
                         size: NSSize(width: 340, height: 330))
    }

    private func render(_ content: some View, to directory: URL, name: String,
                        size: NSSize = NSSize(width: 400, height: 700)) async throws {
        let view = NSHostingView(rootView: content.environment(\.controlActiveState, .active)
            .background(Color(nsColor: .windowBackgroundColor)))
        view.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -10000, y: -10000), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.orderOut(nil) }
        window.contentView = view
        window.orderFront(nil)
        try await Task.sleep(for: .seconds(4))   // sprites come from the network
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            .write(to: directory.appendingPathComponent("\(name).png"))
    }

    private func wait(_ condition: @MainActor () -> Bool, file: StaticString = #filePath,
                      line: UInt = #line) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("timed out", file: file, line: line)
        throw CancellationError()
    }
}
