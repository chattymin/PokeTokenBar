import MultipeerConnectivity
import XCTest
@testable import PokeTokenBar

final class MultipeerTradeTransportTests: XCTestCase {
    /// Bonjour service type rules: 1-15 characters, alphanumerics and hyphens only, must not
    /// start or end with a hyphen.
    func testServiceTypeIsValidBonjourServiceType() {
        let serviceType = MultipeerTradeTransport.serviceType
        XCTAssertTrue((1...15).contains(serviceType.count))
        XCTAssertTrue(serviceType.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "-" })
        XCTAssertFalse(serviceType.hasPrefix("-"))
        XCTAssertFalse(serviceType.hasSuffix("-"))
    }

    func testMakeTradePeerUsesDiscoveryInfoCode() {
        let peer = MultipeerTradeTransport.makeTradePeer(displayName: "민수의 Mac", discoveryInfo: ["code": "ABCD1234"])
        XCTAssertEqual(peer.id, "민수의 Mac")
        XCTAssertEqual(peer.nickname, "민수의 Mac")
        XCTAssertEqual(peer.code, "ABCD1234")
    }

    func testMakeTradePeerFallsBackWhenDiscoveryInfoMissing() {
        let peer = MultipeerTradeTransport.makeTradePeer(displayName: "민수의 Mac", discoveryInfo: nil)
        XCTAssertEqual(peer.code, "????")
    }

    // MARK: R5 — clamp the nickname to MCPeerID's constraints (1-63 UTF-8 bytes, not empty).

    func testClampNicknameFallsBackToHostNameWhenEmpty() {
        let clamped = MultipeerTradeTransport.clampNickname("", fallback: "MacBook-Pro")
        XCTAssertEqual(clamped, "MacBook-Pro")
    }

    func testClampNicknameFallsBackWhenOnlyWhitespace() {
        let clamped = MultipeerTradeTransport.clampNickname("   ", fallback: "MacBook-Pro")
        XCTAssertEqual(clamped, "MacBook-Pro")
    }

    func testClampNicknameTruncatesToUTF8ByteBudgetNotCharacterCount() {
        // A single Korean character is 3 bytes in UTF-8 — with a 63-byte budget it can't exceed 21 characters.
        let longKoreanName = String(repeating: "민", count: 30)
        let clamped = MultipeerTradeTransport.clampNickname(longKoreanName, fallback: "fallback")
        XCTAssertLessThanOrEqual(clamped.utf8.count, 63)
        XCTAssertFalse(clamped.isEmpty)
    }

    func testClampNicknameLeavesShortNameUnchanged() {
        let clamped = MultipeerTradeTransport.clampNickname("민수의 Mac", fallback: "fallback")
        XCTAssertEqual(clamped, "민수의 Mac")
    }

    func testClampNicknameProducesValidMCPeerID() {
        // Verifies that constructing a real MCPeerID from the clamped result succeeds without
        // trapping — the whole reason R5 exists.
        let longKoreanName = String(repeating: "가", count: 100)
        let clamped = MultipeerTradeTransport.clampNickname(longKoreanName, fallback: "fallback")
        let peerID = MCPeerID(displayName: clamped)
        XCTAssertFalse(peerID.displayName.isEmpty)
    }

    // MARK: C2 — guarantee 1:1. MCSession supports multi-party connections, so unconditionally
    // accepting invitations would turn send into a broadcast.

    func testInvitationFromAThirdPartyIsRefusedWhileTradingWithSomeone() {
        let accepted = MultipeerTradeTransport.shouldAccept(
            invitationFrom: "Carol", partner: "Bob", invited: nil,
            myKey: "Alice\u{0}AAAA", theirKey: "Carol\u{0}CCCC")
        XCTAssertFalse(accepted, "a third party must not join an established 1:1 trade")
    }

    func testInvitationFromTheCurrentPartnerIsAcceptedAgain() {
        // The case where the current partner tries to reconnect — this must not be blocked by
        // the partner-lock.
        let accepted = MultipeerTradeTransport.shouldAccept(
            invitationFrom: "Bob", partner: "Bob", invited: nil,
            myKey: "Alice\u{0}AAAA", theirKey: "Bob\u{0}BBBB")
        XCTAssertTrue(accepted)
    }

    func testInvitationFromAnUninvitedPeerIsAcceptedWhenFree() {
        let accepted = MultipeerTradeTransport.shouldAccept(
            invitationFrom: "Bob", partner: nil, invited: nil,
            myKey: "Alice\u{0}AAAA", theirKey: "Bob\u{0}BBBB")
        XCTAssertTrue(accepted, "the side that did not click must still be reachable")
    }

    func testCrossedInvitationsAreResolvedSoExactlyOneSideAccepts() {
        // A situation where both sides tapped each other's row, crossing the invitations — if both
        // accept, the same pair ends up with two connections, one of which soon drops, silently
        // resetting the exchange back to the start.
        let aliceKey = "Alice\u{0}AAAA"
        let bobKey = "Bob\u{0}BBBB"
        let aliceAccepts = MultipeerTradeTransport.shouldAccept(
            invitationFrom: "Bob", partner: nil, invited: "Bob", myKey: aliceKey, theirKey: bobKey)
        let bobAccepts = MultipeerTradeTransport.shouldAccept(
            invitationFrom: "Alice", partner: nil, invited: "Alice", myKey: bobKey, theirKey: aliceKey)
        XCTAssertNotEqual(aliceAccepts, bobAccepts, "exactly one side of a crossed invitation may accept")
    }

    func testCrossedInvitationTieBreakUsesTheCodeWhenNicknamesMatch() {
        // The default nickname is the computer name, so two devices can end up with the same
        // name — the nickname alone gives no ordering.
        let firstKey = MultipeerTradeTransport.tiebreakKey(displayName: "MacBook Pro", code: "AAAA1111")
        let secondKey = MultipeerTradeTransport.tiebreakKey(displayName: "MacBook Pro", code: "BBBB2222")
        XCTAssertNotEqual(firstKey, secondKey)
        let firstAccepts = MultipeerTradeTransport.shouldAccept(
            invitationFrom: "MacBook Pro", partner: nil, invited: "MacBook Pro",
            myKey: firstKey, theirKey: secondKey)
        let secondAccepts = MultipeerTradeTransport.shouldAccept(
            invitationFrom: "MacBook Pro", partner: nil, invited: "MacBook Pro",
            myKey: secondKey, theirKey: firstKey)
        XCTAssertNotEqual(firstAccepts, secondAccepts)
    }

    func testTiebreakKeySeparatesNameFromCode() {
        // Concatenating without a separator would make ("ab","c") and ("a","bc") produce the same key.
        XCTAssertNotEqual(MultipeerTradeTransport.tiebreakKey(displayName: "ab", code: "c"),
                          MultipeerTradeTransport.tiebreakKey(displayName: "a", code: "bc"))
    }

    // MARK: NB2 — an invitation that expired without a response must not linger and keep
    // refusing that peer's later invitations.

    func testExpiredInvitationIsClearedWhenNoNewerInvitationWentOut() {
        XCTAssertTrue(MultipeerTradeTransport.shouldClearExpiredInvitation(
            currentGeneration: 1, expiringGeneration: 1, hasPartner: false))
    }

    func testExpiryOfAnOlderInvitationLeavesTheNewerOneAlone() {
        // If an earlier timer wakes up late and clears an invitation that just went out, then when
        // that invitation crosses with the peer's, both sides accept and two connections are
        // created — exactly the state C2 was meant to prevent.
        XCTAssertFalse(MultipeerTradeTransport.shouldClearExpiredInvitation(
            currentGeneration: 2, expiringGeneration: 1, hasPartner: false))
    }

    func testExpiryDoesNothingOnceAPartnerIsFixed() {
        XCTAssertFalse(MultipeerTradeTransport.shouldClearExpiredInvitation(
            currentGeneration: 1, expiringGeneration: 1, hasPartner: true))
    }

    func testClearedInvitationLetsThatPeerBeAcceptedAgain() {
        // The whole point of clearing an expired invitation — after clearing it, that peer's
        // invitation must pass through without hitting the tiebreak.
        let myKey = MultipeerTradeTransport.tiebreakKey(displayName: "Alice", code: "AAAA")
        let theirKey = MultipeerTradeTransport.tiebreakKey(displayName: "Bob", code: "BBBB")
        XCTAssertFalse(MultipeerTradeTransport.shouldAccept(
            invitationFrom: "Bob", partner: nil, invited: "Bob", myKey: myKey, theirKey: theirKey),
            "while our invitation is live the lower-keyed side must refuse")
        XCTAssertTrue(MultipeerTradeTransport.shouldAccept(
            invitationFrom: "Bob", partner: nil, invited: nil, myKey: myKey, theirKey: theirKey),
            "once the expired invitation is cleared their invitation must be accepted")
    }
}
