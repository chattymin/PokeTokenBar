import XCTest
@testable import PokeTokenBar

// MARK: Stubs (this file only)

/// A fake transport that connects two TradeSessions directly, without real networking.
private final class InMemoryTradeTransport: TradeTransport, @unchecked Sendable {
    var onPeerFound: (@Sendable (TradePeer) -> Void)?
    var onPeerLost: (@Sendable (String) -> Void)?
    var onConnected: (@Sendable () -> Void)?
    var onDisconnected: (@Sendable () -> Void)?
    var onMessageReceived: (@Sendable (TradeMessage) -> Void)?
    weak var peer: InMemoryTradeTransport?

    func startDiscovery() {}
    func stopDiscovery() {}
    func connect(to peer: TradePeer) throws {}

    func send(_ message: TradeMessage) throws {
        guard let peer else { throw TradeTransportError.notConnected }
        peer.onMessageReceived?(message)
    }

    /// Both real transport implementations fire onDisconnected on the disconnecting side too
    /// (MCSession's .notConnected, ManualTradeTransport.disconnect) — this stub, which used to
    /// notify only the peer, was unrealistic to that extent.
    func disconnect() {
        guard let disconnectedPeer = peer else { return }
        peer = nil
        disconnectedPeer.peer = nil
        disconnectedPeer.onDisconnected?()
        onDisconnected?()
    }
}

/// Waits until a polling condition becomes true — for verifying callbacks delivered
/// asynchronously via Task { @MainActor in ... }.
@MainActor
private func waitUntil(timeout: TimeInterval = 1, _ condition: @escaping () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    return condition()
}

/// A throwaway defaults suite per session. Connecting sends a hello, and building that hello
/// generates and stores a trade code — on `.standard` that write would land in the real user
/// domain and survive the test run.
private func isolatedDefaults() -> UserDefaults {
    UserDefaults(suiteName: "TradeSessionTests-\(UUID().uuidString)")!
}

@MainActor
private func makeConnectedSessions() -> (TradeSession, TradeSession) {
    let transportA = InMemoryTradeTransport()
    let transportB = InMemoryTradeTransport()
    transportA.peer = transportB
    transportB.peer = transportA
    // Separate suites: two devices never share an identity, so their codes must differ.
    let sessionA = TradeSession(transport: transportA, defaults: isolatedDefaults())
    let sessionB = TradeSession(transport: transportB, defaults: isolatedDefaults())
    transportA.onConnected?()
    transportB.onConnected?()
    return (sessionA, sessionB)
}

private func sampleEntry(baseID: Int) -> DexEntry {
    DexEntry(baseID: baseID, finalID: baseID, chainOrder: [baseID], rarity: .common, caughtAt: Date())
}

@MainActor
final class TradeSessionTests: XCTestCase {
    func testMutualOfferAndAcceptLeadsToCompletion() async {
        let (sessionA, sessionB) = makeConnectedSessions()
        var receivedByA: TradeItem?
        var receivedByB: TradeItem?
        var completedA = false
        var completedB = false
        sessionA.onReadyToCommit = { receivedByA = $0 }
        sessionB.onReadyToCommit = { receivedByB = $0 }
        sessionA.onCompleted = { completedA = true }
        sessionB.onCompleted = { completedB = true }

        let entryA = sampleEntry(baseID: 1)
        let entryB = sampleEntry(baseID: 4)
        sessionA.proposeOffer(.dexEntry(entryA))
        sessionB.proposeOffer(.dexEntry(entryB))
        // The real accept button is only pressed after the offer actually arrives (async delivery),
        // so wait until both offers have arrived — otherwise a late-arriving .offer would invalidate
        // an accept that was already sent.
        let bothOffersArrived = await waitUntil { sessionA.theirOffer != nil && sessionB.theirOffer != nil }
        XCTAssertTrue(bothOffersArrived)
        sessionA.accept()
        sessionB.accept()

        let readyToCommit = await waitUntil { receivedByA != nil && receivedByB != nil }
        XCTAssertTrue(readyToCommit, "both sides should reach onReadyToCommit")

        guard case .dexEntry(let gotByA) = receivedByA else { return XCTFail("A should receive B's offer") }
        guard case .dexEntry(let gotByB) = receivedByB else { return XCTFail("B should receive A's offer") }
        XCTAssertEqual(gotByA.id, entryB.id)
        XCTAssertEqual(gotByB.id, entryA.id)

        sessionA.confirmLocalCommit()
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertFalse(completedA)   // the peer's commitAck hasn't arrived yet
        sessionB.confirmLocalCommit()
        let bothCompleted = await waitUntil { completedA && completedB }
        XCTAssertTrue(bothCompleted)
    }

    func testRejectStopsSessionBeforeCommit() async {
        // Both sides made an offer and A even pressed Accept, but if B sends Reject instead of
        // Accept, neither side must reach commit even though commit would otherwise have been possible.
        let (sessionA, sessionB) = makeConnectedSessions()
        var rejectedReason: String?
        var commitFiredA = false
        var commitFiredB = false
        sessionA.onRejected = { rejectedReason = $0 }
        sessionA.onReadyToCommit = { _ in commitFiredA = true }
        sessionB.onReadyToCommit = { _ in commitFiredB = true }

        sessionA.proposeOffer(.dexEntry(sampleEntry(baseID: 1)))
        sessionB.proposeOffer(.dexEntry(sampleEntry(baseID: 2)))
        let bothOffered = await waitUntil { sessionA.theirOffer != nil && sessionB.theirOffer != nil }
        XCTAssertTrue(bothOffered, "both offers should have been exchanged before reject")

        sessionA.accept()
        sessionB.reject(reason: "마음이 바뀜")

        let rejected = await waitUntil { rejectedReason != nil }
        XCTAssertTrue(rejected)
        XCTAssertEqual(rejectedReason, "마음이 바뀜")
        XCTAssertFalse(commitFiredA)
        XCTAssertFalse(commitFiredB)
    }

    func testAcceptWithoutBothOffersDoesNotCommit() async {
        // onReadyToCommit must be attached on both sides — a defect where B fires commit (without
        // its own offer) after sending only Accept without an offer would be hidden if we only
        // watched A's side.
        let (sessionA, sessionB) = makeConnectedSessions()
        var commitFiredA = false
        var commitFiredB = false
        sessionA.onReadyToCommit = { _ in commitFiredA = true }
        sessionB.onReadyToCommit = { _ in commitFiredB = true }

        sessionA.proposeOffer(.dexEntry(sampleEntry(baseID: 1)))
        sessionA.accept()
        sessionB.accept()   // B hasn't sent its own offer yet

        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(commitFiredA)
        XCTAssertFalse(commitFiredB)
    }

    func testOfferChangeAfterAcceptInvalidatesStaleAccept() async {
        // A offers X, B accepts X, then A withdraws X and offers Y. B's earlier Accept was
        // consent to X, not Y — it must not silently carry over and let B commit into
        // receiving something it never agreed to.
        let (sessionA, sessionB) = makeConnectedSessions()
        var commitFiredB = false
        sessionB.onReadyToCommit = { _ in commitFiredB = true }

        sessionB.proposeOffer(.dexEntry(sampleEntry(baseID: 9)))
        sessionA.proposeOffer(.dexEntry(sampleEntry(baseID: 1)))   // X
        let firstOfferSeen = await waitUntil {
            if case .dexEntry(let entry) = sessionB.theirOffer { return entry.baseID == 1 }
            return false
        }
        XCTAssertTrue(firstOfferSeen)

        sessionB.accept()

        sessionA.withdrawOffer()
        sessionA.proposeOffer(.dexEntry(sampleEntry(baseID: 2)))   // Y
        let secondOfferSeen = await waitUntil {
            if case .dexEntry(let entry) = sessionB.theirOffer { return entry.baseID == 2 }
            return false
        }
        XCTAssertTrue(secondOfferSeen)

        sessionA.accept()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(commitFiredB, "B's stale accept of X must not carry over to Y")
    }

    func testDuplicateCommitAckDoesNotRefireCompletion() async {
        let (sessionA, sessionB) = makeConnectedSessions()
        var completedCountA = 0
        var commitFiredA = false
        var commitFiredB = false
        sessionA.onCompleted = { completedCountA += 1 }
        sessionA.onReadyToCommit = { _ in commitFiredA = true }
        sessionB.onReadyToCommit = { _ in commitFiredB = true }

        sessionA.proposeOffer(.dexEntry(sampleEntry(baseID: 1)))
        sessionB.proposeOffer(.dexEntry(sampleEntry(baseID: 2)))
        // If accept() is called before the offer arrives, the late-arriving .offer invalidates that
        // accept and commit is never reached — then, despite its name, this test would never exercise
        // the "duplicate ack" path.
        let bothReady = await waitUntil { sessionA.theirOffer != nil && sessionB.theirOffer != nil }
        XCTAssertTrue(bothReady)
        sessionA.accept()
        sessionB.accept()
        let bothCommitted = await waitUntil { commitFiredA && commitFiredB }
        XCTAssertTrue(bothCommitted, "the duplicate-ack path is only reachable after a real commit")

        sessionA.confirmLocalCommit()
        sessionB.confirmLocalCommit()
        let completedOnce = await waitUntil { completedCountA == 1 }
        XCTAssertTrue(completedOnce)

        // Simulate a duplicate commitAck — even if B resends its ack, A's completion must not refire.
        sessionB.confirmLocalCommit()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(completedCountA, 1, "duplicate commitAck must not refire onCompleted")
    }

    /// Regression guard: the hello a session sends must come from the defaults it was handed.
    /// Before injection, `sendHello` read `TradeIdentity` with its `.standard` default, so merely
    /// connecting two stub transports in a test generated and persisted a `tradeCode` in the real
    /// user domain. Asserting the peer's code equals the injected suite's code is what fails there —
    /// `.standard` would hand over a different (or pre-existing) code.
    func testHelloUsesTheInjectedDefaultsAndLeavesStandardUntouched() async {
        let standardCodeBefore = UserDefaults.standard.string(forKey: "tradeCode")
        let defaultsB = isolatedDefaults()
        let transportA = InMemoryTradeTransport()
        let transportB = InMemoryTradeTransport()
        transportA.peer = transportB
        transportB.peer = transportA
        let sessionA = TradeSession(transport: transportA, defaults: isolatedDefaults())
        let sessionB = TradeSession(transport: transportB, defaults: defaultsB)
        transportB.onConnected?()

        let identified = await waitUntil { sessionA.peerIdentity != nil }
        XCTAssertTrue(identified)
        XCTAssertEqual(sessionA.peerIdentity?.code, TradeIdentity.code(defaults: defaultsB))
        XCTAssertEqual(UserDefaults.standard.string(forKey: "tradeCode"), standardCodeBefore,
                       "a trade session must not write an identity into the real user domain")
        _ = sessionB
    }

    func testPeerIdentifiedFiresFromHelloExchangedOnConnect() async {
        // sessionB must stay alive until its deferred onConnected Task runs and sends
        // its hello — discarding it into `_` would let ARC free it (and its transport)
        // before that Task fires, so A would never receive B's hello.
        let (sessionA, sessionB) = makeConnectedSessions()
        let identified = await waitUntil { sessionA.peerIdentity != nil }
        XCTAssertTrue(identified)
        _ = sessionB
    }

    /// The shape `TradeView.onReadyToCommit` originally had: a callback the session stores, capturing
    /// the session strongly. That is a self-retain cycle, so dropping every outside reference leaks
    /// the session *and* the transport it owns — and the leaked callbacks keep firing into the view
    /// that let it go. Documented here because the leak is invisible at the call site.
    func testStronglySelfCapturingCallbackLeaksTheSession() {
        weak var leaked: TradeSession?
        do {
            let session = TradeSession(transport: InMemoryTradeTransport(), defaults: isolatedDefaults())
            leaked = session
            session.onCompleted = { _ = session.myOffer }
        }
        XCTAssertNotNil(leaked, "a strongly self-capturing callback keeps the session alive forever")

        leaked?.onCompleted = nil
        XCTAssertNil(leaked, "clearing the callback breaks the cycle")
    }

    /// Regression guard for the fix: capturing the session weakly lets it deallocate as soon as its
    /// owner drops it, which also releases the transport underneath.
    func testWeaklySelfCapturingCallbackDoesNotRetainTheSession() {
        weak var observed: TradeSession?
        do {
            let session = TradeSession(transport: InMemoryTradeTransport(), defaults: isolatedDefaults())
            observed = session
            session.onCompleted = { [weak session] in _ = session?.myOffer }
        }
        XCTAssertNil(observed, "weak capture must let the session deallocate once its owner drops it")
    }

    func testWithdrawnOfferNotifiesTheReviewingSide() async {
        // If the peer withdraws its offer, the snapshot left on the review screen promises an item
        // that no longer exists — that screen's approve button is blocked by commitIfBothAccepted's
        // theirOffer guard and does nothing.
        let (sessionA, sessionB) = makeConnectedSessions()
        var withdrawnSeenByB = false
        var commitFiredB = false
        sessionB.onOfferWithdrawn = { withdrawnSeenByB = true }
        sessionB.onReadyToCommit = { _ in commitFiredB = true }

        sessionB.proposeOffer(.dexEntry(sampleEntry(baseID: 9)))
        sessionA.proposeOffer(.dexEntry(sampleEntry(baseID: 1)))
        let offerSeen = await waitUntil { sessionB.theirOffer != nil }
        XCTAssertTrue(offerSeen)

        sessionA.withdrawOffer()
        let withdrawn = await waitUntil { withdrawnSeenByB }
        XCTAssertTrue(withdrawn, "the reviewing side must be told the offer is gone")
        XCTAssertNil(sessionB.theirOffer)

        sessionB.accept()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(commitFiredB, "accepting a withdrawn offer must not commit")
    }

    func testWithdrawnOfferKeepsTheLocalOffer() async {
        // My own offer stays put even when the peer withdraws theirs — forcing me to pick again
        // would push the screen back right before approval.
        let (sessionA, sessionB) = makeConnectedSessions()
        sessionB.proposeOffer(.dexEntry(sampleEntry(baseID: 9)))
        sessionA.proposeOffer(.dexEntry(sampleEntry(baseID: 1)))
        let offerSeen = await waitUntil { sessionB.theirOffer != nil }
        XCTAssertTrue(offerSeen)

        sessionA.withdrawOffer()
        let withdrawn = await waitUntil { sessionB.theirOffer == nil }
        XCTAssertTrue(withdrawn)
        XCTAssertNotNil(sessionB.myOffer)
    }

    func testDisconnectBeforeCommitNotifiesBothSidesAndCommitsNothing() async {
        // The "mid-session disconnect" case required by the spec's test strategy — if the connection
        // drops after offers have been exchanged, neither side must reach commit, and both sides must
        // be notified of the disconnect so the screen doesn't hang.
        let (sessionA, sessionB) = makeConnectedSessions()
        var disconnectedA = false
        var disconnectedB = false
        var commitFiredA = false
        var commitFiredB = false
        sessionA.onDisconnected = { disconnectedA = true }
        sessionB.onDisconnected = { disconnectedB = true }
        sessionA.onReadyToCommit = { _ in commitFiredA = true }
        sessionB.onReadyToCommit = { _ in commitFiredB = true }

        sessionA.proposeOffer(.dexEntry(sampleEntry(baseID: 1)))
        sessionB.proposeOffer(.dexEntry(sampleEntry(baseID: 2)))
        let bothOffered = await waitUntil { sessionA.theirOffer != nil && sessionB.theirOffer != nil }
        XCTAssertTrue(bothOffered)

        sessionA.accept()   // A even accepted, but the connection drops before B's accept
        sessionB.disconnect()

        let bothNotified = await waitUntil { disconnectedA && disconnectedB }
        XCTAssertTrue(bothNotified, "both sides must learn the connection is gone")
        XCTAssertFalse(commitFiredA)
        XCTAssertFalse(commitFiredB)
    }

    func testAcceptAfterDisconnectDoesNotCommit() async {
        // The path where the accept button is still on screen after disconnect and gets pressed —
        // since send fails, myAcceptSent never gets set, so commit must not be reached (otherwise
        // only my save would change while the peer received nothing).
        let (sessionA, sessionB) = makeConnectedSessions()
        var commitFiredA = false
        sessionA.onReadyToCommit = { _ in commitFiredA = true }

        sessionA.proposeOffer(.dexEntry(sampleEntry(baseID: 1)))
        sessionB.proposeOffer(.dexEntry(sampleEntry(baseID: 2)))
        let bothOffered = await waitUntil { sessionA.theirOffer != nil && sessionB.theirOffer != nil }
        XCTAssertTrue(bothOffered)
        // The disconnect must happen **after** the peer's accept has actually arrived for this test
        // to exercise the path its name describes — waiting on a condition that's already true
        // (theirOffer != nil) would pass even if the accept never arrived, making it impossible to
        // tell "passed because commit was never possible" apart from "blocked by the disconnect."
        sessionB.accept()
        let theirAcceptArrived = await waitUntil { sessionA.theirAcceptReceived }
        XCTAssertTrue(theirAcceptArrived, "B's accept must reach A before the disconnect")

        // At this point A has myOffer, theirOffer, and theirAcceptReceived all set, and hasn't
        // committed yet — the only thing blocking commit is the failed accept send.
        sessionA.disconnect()
        sessionA.accept()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(commitFiredA, "a failed accept send must not reach commit")
    }
}
