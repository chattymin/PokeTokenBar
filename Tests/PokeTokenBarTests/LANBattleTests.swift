import XCTest
@testable import PokeTokenBar

final class LANBattleTests: XCTestCase {
    func testFramingHandlesFragmentationAndRejectsInvalidLengths() throws {
        let frame = try LANBattleCodec.encode(.command(revision: 1, moveID: "tackle"))
        var partial = Data(frame.prefix(3))
        XCTAssertTrue(try LANBattleCodec.extract(from: &partial).isEmpty)
        partial.append(frame.dropFirst(3))
        XCTAssertEqual(try LANBattleCodec.extract(from: &partial).count, 1)
        XCTAssertTrue(partial.isEmpty)
        var zero = Data([0, 0, 0, 0])
        XCTAssertThrowsError(try LANBattleCodec.extract(from: &zero))
        var tooLarge = UInt32(LANBattleCodec.maximumPayload + 1).bigEndian
        var oversized = Data(bytes: &tooLarge, count: 4)
        XCTAssertThrowsError(try LANBattleCodec.extract(from: &oversized))
    }

    @MainActor func testLANChoicesMustBelongToThatFighter() throws {
        let state = try BattleState(first: pokemon("first"), second: pokemon("second"), seed: 1234)
        XCTAssertTrue(LANBattleSession.validChoice("tackle", side: 0, state: state))
        XCTAssertFalse(LANBattleSession.validChoice("unknown", side: 0, state: state))
        XCTAssertFalse(LANBattleSession.validChoice("tackle", side: 2, state: state))
    }

    func testSeededCommandReplayDetectsReplacedGuestChoice() throws {
        var host = try BattleState(first: pokemon("first"), second: pokemon("second"), seed: 1234)
        var guest = try BattleState(first: pokemon("first"), second: pokemon("second"), seed: 1234)
        var tampered = try BattleState(first: pokemon("first"), second: pokemon("second"), seed: 1234)
        XCTAssertEqual(host, guest)
        _ = try host.resolve(firstMoveID: "tackle", secondMoveID: "growl")
        _ = try guest.resolve(firstMoveID: "tackle", secondMoveID: "growl")
        _ = try tampered.resolve(firstMoveID: "growl", secondMoveID: "tackle")
        XCTAssertEqual(host, guest)
        XCTAssertNotEqual(host, tampered)
    }

    private func pokemon(_ id: String) -> BattleCombatant {
        BattleCombatant(id: id, speciesID: 1, name: "Bulbasaur", level: 50,
                        types: ["grass"],
                        stats: BattleStats(hp: 100, attack: 50, defense: 50,
                                          specialAttack: 50, specialDefense: 50, speed: 50),
                        moves: [BattleMoveCatalog.move(named: "tackle")!,
                                BattleMoveCatalog.move(named: "growl")!])
    }
}
