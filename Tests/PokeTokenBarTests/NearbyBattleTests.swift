import MultipeerConnectivity
import XCTest
@testable import PokeTokenBar

@MainActor
final class NearbyBattleTests: XCTestCase {
    func testFoundTrainersAreDeduplicatedSortedAndMarkedByVersion() {
        let service = NearbyBattleService()
        let misty = MCPeerID(displayName: "Misty"), brock = MCPeerID(displayName: "brock")
        let current = [NearbyBattle.versionKey: String(BattleWireMessage.protocolVersion)]
        service.found(misty, info: current)
        service.found(brock, info: [NearbyBattle.versionKey: "99"])
        service.found(misty, info: current)
        XCTAssertEqual(service.trainers.map(\.name), ["brock", "Misty"])
        XCTAssertEqual(service.trainers.map(\.isCompatible), [false, true])
        service.found(brock, info: nil)
        XCTAssertEqual(service.trainers.first { $0.id == brock }?.isCompatible, false)
        service.lost(misty)
        XCTAssertEqual(service.trainers.map(\.name), ["brock"])
    }

    func testInvitationsAreOnlyConsideredWhenVisibleIdleAndReady() throws {
        let hello = try BattleWireMessage.hello(protocolVersion: BattleWireMessage.protocolVersion, trainer: "Ash").encoded()
        func acceptable(_ context: Data? = nil, visible: Bool = true, busy: Bool = false, incoming: Bool = false,
                        team: Bool = true) -> Bool {
            NearbyBattleService.invitationIsAcceptable(context: context, isVisible: visible, isBusy: busy,
                                                       hasIncoming: incoming, hasTeam: team)
        }
        XCTAssertTrue(acceptable(hello))
        XCTAssertFalse(acceptable(hello, visible: false))
        XCTAssertFalse(acceptable(hello, busy: true), "one battle at a time")
        XCTAssertFalse(acceptable(hello, incoming: true), "one open challenge at a time")
        XCTAssertFalse(acceptable(hello, team: false))
        XCTAssertFalse(acceptable(nil))
        XCTAssertFalse(acceptable(Data("junk".utf8)))
        XCTAssertFalse(acceptable(try BattleWireMessage.hello(protocolVersion: 99, trainer: "Future").encoded()))
        XCTAssertFalse(acceptable(try BattleWireMessage.nonce(1).encoded()), "the context must be a hello")
    }

    func testInvitationWhileHiddenIsDeclinedImmediately() throws {
        let service = NearbyBattleService()
        var answer: Bool?
        let hello = try BattleWireMessage.hello(protocolVersion: BattleWireMessage.protocolVersion, trainer: "Ash").encoded()
        service.invited(by: MCPeerID(displayName: "Ash"), context: hello) { accepted, _ in answer = accepted }
        XCTAssertEqual(answer, false)
        XCTAssertNil(service.incoming)
    }

    /// The service type is duplicated in the Info.plist that build-app.sh writes; macOS 15+ silently
    /// blocks Bonjour for a type that is not declared there, which no unit test would otherwise notice.
    func testBundleDeclaresTheBonjourServiceAndLocalNetworkReason() throws {
        let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("scripts/build-app.sh")
        let plist = try String(contentsOf: script, encoding: .utf8)
        XCTAssertTrue(plist.contains("<string>_\(NearbyBattle.serviceType)._tcp</string>"))
        XCTAssertTrue(plist.contains("<string>_\(NearbyBattle.serviceType)._udp</string>"))
        XCTAssertTrue(plist.contains("<key>NSLocalNetworkUsageDescription</key>"))
        let type = NearbyBattle.serviceType
        XCTAssertTrue((1...15).contains(type.count) && type.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "-" },
                      "MultipeerConnectivity rejects other service types at runtime")
    }

    func testRecordCountsNearbyResultsButNotAbortedOnes() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("record-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let store = CompanionStore(fileURL: file)
        for outcome in [BattleSession.Outcome.won, .won, .lost, .draw, .aborted] { store.recordBattle(outcome) }
        XCTAssertEqual(store.battleRecord, BattleRecord(wins: 2, losses: 1, draws: 1))
        XCTAssertEqual(CompanionStore(fileURL: file).battleRecord, BattleRecord(wins: 2, losses: 1, draws: 1))

        var state = CompanionState()
        state.battleRecord = BattleRecord(wins: -4, losses: 3, draws: -1)
        XCTAssertEqual(SaveTransfer.sanitized(state).battleRecord, BattleRecord(wins: 0, losses: 3, draws: 0))
        let old = try JSONDecoder().decode(CompanionState.self, from: Data(#"{"battleRecord":"broken"}"#.utf8))
        XCTAssertEqual(old.battleRecord, BattleRecord())
    }
}
