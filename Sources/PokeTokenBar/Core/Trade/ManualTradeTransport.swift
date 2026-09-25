import Foundation
import Network

/// A one-shot gate that prevents a path where completion gets called twice (e.g. canceling the
/// listener right after a successful connection reports a failed state again). Split into its
/// own class because Swift 6 forbids concurrent access to a captured local var from multiple
/// callback closures — state lives in a reference type instead, protected by NSLock.
private final class OneShotGate: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false

    func fireOnce(_ body: () -> Void) {
        lock.lock()
        let alreadyFired = fired
        fired = true
        lock.unlock()
        guard !alreadyFired else { return }
        body()
    }
}

/// The fallback for when auto-discovery (MultipeerTradeTransport) can't find the peer — a person
/// manually exchanges an IP:port code and connects over TCP, without Bonjour discovery. This
/// class does not discover on its own (startDiscovery/stopDiscovery are intentional no-ops,
/// connect(to:) throws).
/// `listener`/`connection`/`frameBuffer` are accessed concurrently from the Network framework's
/// callback queue (writes) and the caller's thread (reads, send/disconnect), so they're
/// protected with NSLock — following the same lock convention as NetworkReachabilityMonitor: the
/// lock is held only for the short span of copying/swapping a value, and callbacks like
/// onConnected/onDisconnected/onMessageReceived are invoked after releasing it (NSLock is not
/// reentrant, so a callback re-entering this transport while holding the lock would deadlock).
final class ManualTradeTransport: NSObject, TradeTransport, @unchecked Sendable {
    var onPeerFound: (@Sendable (TradePeer) -> Void)?
    var onPeerLost: (@Sendable (String) -> Void)?
    var onConnected: (@Sendable () -> Void)?
    var onDisconnected: (@Sendable () -> Void)?
    var onMessageReceived: (@Sendable (TradeMessage) -> Void)?

    private let lock = NSLock()
    private var listener: NWListener?
    private var connection: NWConnection?
    private var frameBuffer = TCPFrameBuffer()
    /// Whether onDisconnected has already been reported for the current connection — termination
    /// can be detected via either stateUpdateHandler(.failed/.cancelled) or receiveLoop's EOF
    /// check, so the callback must react to only whichever arrives first.
    /// Reset to false each time wire(_:) sets up a new connection.
    private var disconnectNotified = false
    private let queue = DispatchQueue(label: "com.poketokenbar.trade-manual")

    /// Delivers my connection code ("ip:port") to show the peer, via completion. The port is a
    /// system-assigned ephemeral port (NWEndpoint.Port.any) — a hardcoded port would fail its
    /// second bind in test/QA scenarios that run two instances on the same Mac at once.
    /// NWListener reports failures like a port conflict asynchronously via
    /// stateUpdateHandler(.failed) rather than from the initializer, so completion must be a
    /// callback rather than a synchronous return value.
    /// completion is called exactly once whether the outcome is failure or success, but the
    /// timing differs per path — if the local IPv4 can't be found or listener creation itself
    /// fails, it's called synchronously (on the caller's thread) before this function returns;
    /// every other success/failure is called asynchronously on the Network framework's callback
    /// queue. The caller must handle both timings.
    func startListening(completion: @escaping @Sendable (String?) -> Void) {
        guard let address = Self.currentIPv4Address(),
              let newListener = try? NWListener(using: .tcp, on: .any) else {
            completion(nil)
            return
        }

        let gate = OneShotGate()
        let callCompletionOnce: @Sendable (String?) -> Void = { result in
            gate.fireOnce { completion(result) }
        }

        newListener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            self.lock.lock()
            // Trading is 1:1, so only the first connection is accepted. Calling cancel while
            // holding the lock is an intentional exception to this file's "callbacks outside the
            // lock" discipline — NWListener.cancel() dispatches to the queue rather than
            // re-entering the callback.
            self.listener?.cancel()
            self.listener = nil
            self.lock.unlock()
            self.wire(connection)
            connection.start(queue: self.queue)
        }
        newListener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                guard let boundPort = newListener.port else {
                    callCompletionOnce(nil)
                    return
                }
                callCompletionOnce("\(address):\(boundPort.rawValue)")
            case .failed, .cancelled:
                callCompletionOnce(nil)
                self?.lock.lock()
                self?.listener = nil
                self?.lock.unlock()
            default:
                break
            }
        }

        lock.lock()
        listener = newListener
        lock.unlock()
        newListener.start(queue: queue)
    }

    /// Connects directly using the code the peer showed.
    func connectManually(code: String) throws {
        let parts = code.split(separator: ":")
        guard parts.count == 2, let port = UInt16(parts[1]), let nwPort = NWEndpoint.Port(rawValue: port)
        else { throw TradeTransportError.notConnected }
        let connection = NWConnection(host: NWEndpoint.Host(String(parts[0])), port: nwPort, using: .tcp)
        wire(connection)
        connection.start(queue: queue)
    }

    /// Cancels a leftover previous connection (preventing its old stateUpdateHandler from
    /// continuing to fire) and sets up the new one. Needed for the path where connectManually is
    /// called twice in a row (e.g. the user mistypes a code and retries).
    private func wire(_ connection: NWConnection) {
        lock.lock()
        let previousConnection = self.connection
        self.connection = connection
        frameBuffer = TCPFrameBuffer()
        disconnectNotified = false
        lock.unlock()
        previousConnection?.cancel()

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.onConnected?()
                self?.receiveLoop(on: connection)
            case .failed, .cancelled:
                self?.handleConnectionTerminated(connection)
            default:
                break
            }
        }
    }

    /// Reports connection termination exactly once — stateUpdateHandler(.failed/.cancelled) and
    /// receiveLoop's EOF check can both fire, so the signal that arrives later is ignored (an
    /// R20/R21-class issue — prevents send from appearing to succeed on a dead connection). If
    /// this connection has already been replaced by another (wire was called again), do nothing
    /// — the new connection's state must not be overwritten by the old connection's termination.
    private func handleConnectionTerminated(_ terminatedConnection: NWConnection) {
        lock.lock()
        guard connection === terminatedConnection else {
            lock.unlock()
            return
        }
        connection = nil
        let alreadyNotified = disconnectNotified
        disconnectNotified = true
        lock.unlock()
        guard !alreadyNotified else { return }
        onDisconnected?()
    }

    private func receiveLoop(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var decodedMessages: [TradeMessage] = []
            var frameTooLarge = false
            if let data, !data.isEmpty {
                self.lock.lock()
                let frames: [Data]
                do {
                    frames = try self.frameBuffer.append(data)
                } catch {
                    frames = []
                    frameTooLarge = true
                }
                self.lock.unlock()
                for frame in frames {
                    if let message = try? JSONDecoder().decode(TradeMessage.self, from: frame) {
                        decodedMessages.append(message)
                    } else {
                        // Distinguishes, in the logs, a frame we couldn't decode due to a version
                        // mismatch from "the peer simply never made an offer."
                        AppLog.write("trade: undecodable manual frame (\(frame.count) bytes)")
                    }
                }
            }
            for message in decodedMessages {
                self.onMessageReceived?(message)
            }
            if frameTooLarge {
                connection.cancel()   // A manipulated length prefix — close the connection instead of stalling silently (R23).
                self.handleConnectionTerminated(connection)
            } else if isComplete || error != nil {
                self.handleConnectionTerminated(connection)
            } else {
                self.receiveLoop(on: connection)
            }
        }
    }

    // Auto-discovery is not supported (manual connection only).
    func startDiscovery() {}
    func stopDiscovery() {}
    func connect(to peer: TradePeer) throws { throw TradeTransportError.notConnected }

    func send(_ message: TradeMessage) throws {
        lock.lock()
        let currentConnection = connection
        lock.unlock()
        guard let currentConnection else { throw TradeTransportError.sendFailed }
        guard let data = try? JSONEncoder().encode(message) else { throw TradeTransportError.sendFailed }
        currentConnection.send(content: TCPFrameBuffer.frame(data), completion: .contentProcessed { _ in })
    }

    func disconnect() {
        lock.lock()
        let currentConnection = connection
        let currentListener = listener
        connection = nil
        listener = nil
        frameBuffer = TCPFrameBuffer()   // Don't let the next connection's framing get corrupted by leftover bytes from this one.
        let alreadyNotified = disconnectNotified
        disconnectNotified = true
        lock.unlock()
        currentConnection?.cancel()
        currentListener?.cancel()
        // Only report a disconnect if there was a connection — before connecting (when only the
        // listener is being canceled), nothing was actually torn down.
        // NWConnection.cancel()'s later stateUpdateHandler(.cancelled) callback finds connection
        // already nil and is silently ignored in handleConnectionTerminated (avoids a duplicate
        // notification).
        if currentConnection != nil, !alreadyNotified {
            onDisconnected?()
        }
    }

    /// en0/en1 IPv4 — only looks at the Mac's typical Wi-Fi/Ethernet interfaces (virtual/loopback
    /// interfaces excluded).
    static func currentIPv4Address() -> String? {
        var address: String?
        var ifaddrPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPointer) == 0, let firstAddr = ifaddrPointer else { return nil }
        defer { freeifaddrs(ifaddrPointer) }
        for pointer in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: interface.ifa_name)
            guard name == "en0" || name == "en1" else { continue }
            var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                       &hostBuffer, socklen_t(hostBuffer.count), nil, 0, NI_NUMERICHOST)
            // getnameinfo NUL-terminates its output — stop there so trailing buffer padding doesn't end up in the string.
            address = String(decoding: hostBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            break
        }
        return address
    }
}
