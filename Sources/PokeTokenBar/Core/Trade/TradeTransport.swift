import Foundation

/// A discovered candidate peer — the minimal info needed to show it in the discovery list.
struct TradePeer: Identifiable, Equatable, Sendable {
    let id: String
    let nickname: String
    let code: String
}

enum TradeTransportError: Error, Equatable {
    case notConnected
    case sendFailed
    case discoveryTimedOut
}

/// The transport layer for a trade session — `TradeSession` doesn't need to know which mechanism
/// (Multipeer auto-discovery / manual TCP) made the connection. Callbacks may be invoked on any
/// thread — the MainActor consumer (TradeSession) hops itself
/// (same convention as NetworkReachabilityMonitor.onReconnected).
protocol TradeTransport: AnyObject {
    var onPeerFound: (@Sendable (TradePeer) -> Void)? { get set }
    var onPeerLost: (@Sendable (String) -> Void)? { get set }
    var onConnected: (@Sendable () -> Void)? { get set }
    var onDisconnected: (@Sendable () -> Void)? { get set }
    var onMessageReceived: (@Sendable (TradeMessage) -> Void)? { get set }

    func startDiscovery()
    func stopDiscovery()
    func connect(to peer: TradePeer) throws
    func send(_ message: TradeMessage) throws
    func disconnect()
}
