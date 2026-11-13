import AppKit
import Network
import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor
final class BattleTests: XCTestCase {
    private func member(_ dex: Int, level: Int, moves: [String]) -> BattleTeamMember {
        var profile = PokemonProfile.generate(seed: UInt64(dex))
        profile.level = level
        profile.gender = .male
        profile.moves = moves.map { PokemonKnownMove(name: $0, learnedAtLevel: 1) }
        let entry = DexEntry(baseID: dex, finalID: dex, chainOrder: [dex], rarity: .common, caughtAt: nil,
                             nature: .adamant, profile: profile)
        return BattleTeamMember(entry: entry, name: "Mon\(dex)")
    }

    private var ash: BattlePlayer {
        BattlePlayer(name: "Ash", team: [member(3, level: 50, moves: ["vine-whip", "tackle"]),
                                         member(25, level: 30, moves: ["thunder-shock"])])
    }
    private var gary: BattlePlayer {
        BattlePlayer(name: "Gary", team: [member(9, level: 50, moves: ["water-gun", "bite"]),
                                          member(143, level: 45, moves: ["body-slam"])])
    }

    private func firstChoice(_ request: BattleSnapshot.Request) -> String? {
        switch request.kind {
        case "move": return request.moves?.first { !$0.disabled }.map { "move \($0.slot)" }
        case "switch": return request.switches?.first.map { "switch \($0)" }
        default: return nil
        }
    }

    func testEngineUsesProfileDataAndRealLevels() throws {
        let snapshots = try BattleEngine().start(host: ash, guest: gary)
        let p1 = try XCTUnwrap(snapshots[.p1]), p2 = try XCTUnwrap(snapshots[.p2])
        XCTAssertEqual(p1.me.team.map(\.level), [50, 30])
        XCTAssertEqual(p1.request.moves?.map(\.name), ["Vine Whip", "Tackle"])
        // The opponent is seen as a percentage and only once revealed.
        XCTAssertEqual(p1.foe.team.map(\.dex), [9])
        XCTAssertEqual(p1.foe.active?.maxhp, 100)
        XCTAssertEqual(p2.me.active?.dex, 9)
        XCTAssertEqual(p1.foe.left, 2)
    }

    func testEngineRejectsIllegalChoicesAndUnknownSpecies() throws {
        let engine = try BattleEngine()
        _ = try engine.start(host: ash, guest: gary)
        XCTAssertThrowsError(try engine.choose(.p1, "move 4"))      // only two moves
        XCTAssertThrowsError(try engine.choose(.p1, "switch 1"))    // already active
        XCTAssertThrowsError(try engine.choose(.p1, "team 123"))    // not a battle choice
        XCTAssertNoThrow(try engine.choose(.p1, "move 1"))

        var bogus = gary
        bogus.team[0].dex = 99_999
        XCTAssertThrowsError(try engine.start(host: ash, guest: bogus))
    }

    func testEnginePlaysABattleToTheEnd() throws {
        let engine = try BattleEngine()
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
        let host = BattleSession(advertises: false), guest = BattleSession(advertises: false)
        defer { host.stop(); guest.stop() }
        host.enterLobby(as: ash)
        guest.enterLobby(as: gary)
        try await wait { host.port != nil }
        let port = try XCTUnwrap(host.port)

        guest.challenge(endpoint: .hostPort(host: "127.0.0.1", port: port), name: "Ash")
        try await wait { host.phase == .incoming("Gary") }
        host.accept()
        try await wait { guest.phase == .battle }
        XCTAssertEqual(guest.snapshot?.me.active?.dex, 9)
        XCTAssertEqual(host.snapshot?.me.active?.dex, 3)

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
        let host = BattleSession(advertises: false), guest = BattleSession(advertises: false)
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

    /// Opt-in: renders the battle screen from a live loopback battle (used for PR images).
    func testRenderBattleScreen() async throws {
        guard let path = ProcessInfo.processInfo.environment["PTB_BATTLE_SCREENSHOT_DIR"] else {
            throw XCTSkip("set PTB_BATTLE_SCREENSHOT_DIR to render")
        }
        let host = BattleSession(advertises: false), guest = BattleSession(advertises: false)
        defer { host.stop(); guest.stop() }
        host.enterLobby(as: ash)
        guest.enterLobby(as: gary)
        try await wait { host.port != nil }
        guest.challenge(endpoint: .hostPort(host: "127.0.0.1", port: try XCTUnwrap(host.port)), name: "Ash")
        try await wait { host.phase == .incoming("Gary") }
        host.accept()
        try await wait { guest.phase == .battle }
        host.choose("move 1")
        guest.choose("move 1")
        try await wait { host.snapshot?.turn == 2 }

        let store = CompanionStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("battle-render-\(UUID().uuidString).json"))
        let view = NSHostingView(rootView: BattleView(store: store, session: host, playerName: "Ash")
            .background(Color(nsColor: .windowBackgroundColor)))
        view.frame = NSRect(x: 0, y: 0, width: 400, height: 620)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        try await Task.sleep(for: .seconds(4))   // sprites come from the network
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let directory = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            .write(to: directory.appendingPathComponent("battle.png"))
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
