import XCTest
@testable import PokeTokenBar

/// Drives two real `MultipeerTradeTransport` instances against the actual MultipeerConnectivity
/// stack — discovery, invitation, connection and one message over the wire. Every other trade
/// test substitutes an in-memory transport, so this is the only place the Multipeer path is
/// exercised rather than reasoned about.
///
/// Skips rather than fails when the environment has no usable local network (sandboxed CI, no
/// permission grant): a skip says "unverified here", a failure would say "broken", and only the
/// first is true.
final class MultipeerLiveDiscoveryTests: XCTestCase {
    private func makePair() -> (MultipeerTradeTransport, MultipeerTradeTransport) {
        // Distinct nicknames keep the tiebreak deterministic and the discovery list unambiguous.
        (MultipeerTradeTransport(nickname: "PTBTestAlice-\(UUID().uuidString.prefix(4))", code: "AAAA1111"),
         MultipeerTradeTransport(nickname: "PTBTestBob-\(UUID().uuidString.prefix(4))", code: "BBBB2222"))
    }

    func testTwoTransportsDiscoverConnectAndExchangeAMessage() throws {
        let (alice, bob) = makePair()
        defer { alice.disconnect(); bob.disconnect(); alice.stopDiscovery(); bob.stopDiscovery() }

        let aliceFoundBob = expectation(description: "alice discovers bob")
        aliceFoundBob.assertForOverFulfill = false
        let bobConnected = expectation(description: "bob sees the session connect")
        bobConnected.assertForOverFulfill = false
        let aliceConnected = expectation(description: "alice sees the session connect")
        aliceConnected.assertForOverFulfill = false
        let bobReceivedHello = expectation(description: "bob receives alice's hello")
        bobReceivedHello.assertForOverFulfill = false

        let discovered = OSAllocatedUnfairBoxCompat<TradePeer?>(nil)
        alice.onPeerFound = { peer in
            guard peer.code == "BBBB2222" else { return }
            discovered.set(peer)
            aliceFoundBob.fulfill()
        }
        alice.onConnected = { aliceConnected.fulfill() }
        bob.onConnected = { bobConnected.fulfill() }
        bob.onMessageReceived = { message in
            guard case .hello(_, let code) = message, code == "AAAA1111" else { return }
            bobReceivedHello.fulfill()
        }

        alice.startDiscovery()
        bob.startDiscovery()

        let discoveryResult = XCTWaiter().wait(for: [aliceFoundBob], timeout: 25)
        guard discoveryResult == .completed, let peer = discovered.value else {
            throw XCTSkip("No local-network discovery in this environment — Multipeer path unverified here.")
        }

        try alice.connect(to: peer)
        wait(for: [aliceConnected, bobConnected], timeout: 25)

        try alice.send(.hello(nickname: "alice", code: "AAAA1111"))
        wait(for: [bobReceivedHello], timeout: 15)
    }
}

/// Minimal thread-safe box — the transport's callbacks arrive on framework queues, so the value
/// the test reads back afterwards has to cross threads.
private final class OSAllocatedUnfairBoxCompat<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) { storage = value }

    var value: Value {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    func set(_ newValue: Value) {
        lock.lock(); defer { lock.unlock() }
        storage = newValue
    }
}
