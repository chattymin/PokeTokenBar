import XCTest
@testable import PokeTokenBar

final class TradeMessageTests: XCTestCase {
    private func roundTrip(_ message: TradeMessage) throws -> TradeMessage {
        let data = try JSONEncoder().encode(message)
        return try JSONDecoder().decode(TradeMessage.self, from: data)
    }

    func testHelloRoundTrips() throws {
        guard case .hello(let nickname, let code) = try roundTrip(.hello(nickname: "테스트", code: "ABCD1234")) else {
            return XCTFail("expected hello")
        }
        XCTAssertEqual(nickname, "테스트")
        XCTAssertEqual(code, "ABCD1234")
    }

    func testOfferRoundTripsDexEntry() throws {
        let entry = DexEntry(baseID: 1, finalID: 1, chainOrder: [1], rarity: .common, caughtAt: Date())
        guard case .offer(.dexEntry(let result)) = try roundTrip(.offer(.dexEntry(entry))) else {
            return XCTFail("expected offer(.dexEntry)")
        }
        XCTAssertEqual(result.id, entry.id)
    }

    func testRejectRoundTripsReason() throws {
        guard case .reject(let reason) = try roundTrip(.reject(reason: "마음이 바뀜")) else {
            return XCTFail("expected reject")
        }
        XCTAssertEqual(reason, "마음이 바뀜")
    }

    func testCommitAndCommitAckRoundTripNonce() throws {
        guard case .commit(let nonce) = try roundTrip(.commit(nonce: "abc-123")) else {
            return XCTFail("expected commit")
        }
        XCTAssertEqual(nonce, "abc-123")
        guard case .commitAck(let ackNonce) = try roundTrip(.commitAck(nonce: "abc-123")) else {
            return XCTFail("expected commitAck")
        }
        XCTAssertEqual(ackNonce, "abc-123")
    }

    func testOfferWithdrawnAndAcceptRoundTripWithNoPayload() throws {
        guard case .offerWithdrawn = try roundTrip(.offerWithdrawn) else { return XCTFail("expected offerWithdrawn") }
        guard case .accept = try roundTrip(.accept) else { return XCTFail("expected accept") }
    }
}
