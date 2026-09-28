import XCTest
@testable import PokeTokenBar

final class ManualTradeTransportTests: XCTestCase {
    func testConnectManuallyRejectsMalformedCode() {
        let transport = ManualTradeTransport()
        XCTAssertThrowsError(try transport.connectManually(code: "not-a-valid-code"))
    }

    func testSendBeforeConnectionThrowsSendFailed() {
        let transport = ManualTradeTransport()
        XCTAssertThrowsError(try transport.send(.accept)) { error in
            XCTAssertEqual(error as? TradeTransportError, .sendFailed)
        }
    }

    func testLoopbackConnectionExchangesOneMessage() throws {
        let listenerSide = ManualTradeTransport()
        addTeardownBlock { listenerSide.disconnect() }
        let listeningStarted = expectation(description: "listener started")
        nonisolated(unsafe) var listenerCode: String?
        listenerSide.startListening { code in
            listenerCode = code
            listeningStarted.fulfill()
        }
        wait(for: [listeningStarted], timeout: 5)
        guard let code = listenerCode else {
            throw XCTSkip("No local IPv4 address in this environment — run on a local dev Mac")
        }
        let connectorSide = ManualTradeTransport()
        addTeardownBlock { connectorSide.disconnect() }

        let listenerConnected = expectation(description: "listener connected")
        let connectorConnected = expectation(description: "connector connected")
        let messageReceived = expectation(description: "message received")
        listenerSide.onConnected = { listenerConnected.fulfill() }
        connectorSide.onConnected = { connectorConnected.fulfill() }
        listenerSide.onMessageReceived = { message in
            guard case .accept = message else { return }
            messageReceived.fulfill()
        }

        try connectorSide.connectManually(code: code)
        wait(for: [listenerConnected, connectorConnected], timeout: 5)
        try connectorSide.send(.accept)
        wait(for: [messageReceived], timeout: 5)
    }

    /// R20 regression — when the peer disconnects, this side's `connection` must be cleared.
    /// Otherwise a send on the dead NWConnection "succeeds" without an error, which leads
    /// TradeSession.confirmLocalCommit() into a desync where it treats a message that was never
    /// actually delivered as if it had been.
    func testSendAfterPeerDisconnectionThrowsSendFailed() throws {
        let listenerSide = ManualTradeTransport()
        addTeardownBlock { listenerSide.disconnect() }
        let listeningStarted = expectation(description: "listener started")
        nonisolated(unsafe) var listenerCode: String?
        listenerSide.startListening { code in
            listenerCode = code
            listeningStarted.fulfill()
        }
        wait(for: [listeningStarted], timeout: 5)
        guard let code = listenerCode else {
            throw XCTSkip("No local IPv4 address in this environment — run on a local dev Mac")
        }
        let connectorSide = ManualTradeTransport()
        addTeardownBlock { connectorSide.disconnect() }

        let listenerConnected = expectation(description: "listener connected")
        let connectorConnected = expectation(description: "connector connected")
        listenerSide.onConnected = { listenerConnected.fulfill() }
        connectorSide.onConnected = { connectorConnected.fulfill() }
        try connectorSide.connectManually(code: code)
        wait(for: [listenerConnected, connectorConnected], timeout: 5)

        let connectorNoticedDisconnect = expectation(description: "connector noticed peer disconnect")
        connectorNoticedDisconnect.assertForOverFulfill = true
        connectorSide.onDisconnected = { connectorNoticedDisconnect.fulfill() }
        listenerSide.disconnect()
        wait(for: [connectorNoticedDisconnect], timeout: 5)

        XCTAssertThrowsError(try connectorSide.send(.accept)) { error in
            XCTAssertEqual(error as? TradeTransportError, .sendFailed)
        }
    }

    /// R21 regression — the previous version only checked "completion was called once," which really
    /// verified "at least once" (it never triggered a second transition, so assertForOverFulfill had
    /// nothing to catch). Here, after success, disconnect() cancels the listener so
    /// stateUpdateHandler(.cancelled) calls callCompletionOnce again, and we actually verify that
    /// OneShotGate suppresses that second call.
    func testStartListeningCompletionFiresExactlyOnce() throws {
        let transport = ManualTradeTransport()
        addTeardownBlock { transport.disconnect() }
        let completionCalled = expectation(description: "completion called once")
        completionCalled.assertForOverFulfill = true
        transport.startListening { _ in
            completionCalled.fulfill()
        }
        wait(for: [completionCalled], timeout: 5)

        transport.disconnect()   // cancels the listener — re-entering .cancelled triggers a second completion call.
        let settled = expectation(description: "allow time for a suppressed second call to surface")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { settled.fulfill() }
        wait(for: [settled], timeout: 1)
    }

    /// R22 regression — when connectManually is called again to switch to a different peer, failing
    /// to cancel the previous connection leaves the old peer believing the connection is still alive
    /// (a socket leak plus the old stateUpdateHandler staying alive). Whether the previous connection
    /// was actually cancelled is observed through whether the peer (firstListener) detects the
    /// disconnect — if only the self.connection pointer were swapped, firstListener would never know.
    func testReconnectingCancelsPreviousConnection() throws {
        let firstListener = ManualTradeTransport()
        addTeardownBlock { firstListener.disconnect() }
        let secondListener = ManualTradeTransport()
        addTeardownBlock { secondListener.disconnect() }
        let connectorSide = ManualTradeTransport()
        addTeardownBlock { connectorSide.disconnect() }

        let firstListenerCodeReady = expectation(description: "first listener started")
        nonisolated(unsafe) var firstCode: String?
        firstListener.startListening { code in
            firstCode = code
            firstListenerCodeReady.fulfill()
        }
        let secondListenerCodeReady = expectation(description: "second listener started")
        nonisolated(unsafe) var secondCode: String?
        secondListener.startListening { code in
            secondCode = code
            secondListenerCodeReady.fulfill()
        }
        wait(for: [firstListenerCodeReady, secondListenerCodeReady], timeout: 5)
        guard let codeA = firstCode, let codeB = secondCode else {
            throw XCTSkip("No local IPv4 address in this environment — run on a local dev Mac")
        }

        let firstConnected = expectation(description: "connected to first listener")
        firstListener.onConnected = { firstConnected.fulfill() }
        try connectorSide.connectManually(code: codeA)
        wait(for: [firstConnected], timeout: 5)

        let firstListenerNoticedDisconnect = expectation(description: "first listener noticed disconnect")
        firstListener.onDisconnected = { firstListenerNoticedDisconnect.fulfill() }
        let secondConnected = expectation(description: "connected to second listener")
        secondListener.onConnected = { secondConnected.fulfill() }

        try connectorSide.connectManually(code: codeB)   // reconnects to a different peer — the previous connection must be cancelled.
        wait(for: [firstListenerNoticedDisconnect, secondConnected], timeout: 5)
    }
}
