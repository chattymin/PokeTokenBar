import Foundation

/// Messages exchanged during a trade session. Sent as JSON regardless of transport
/// (Multipeer/manual TCP). All associated values are Codable, so the compiler synthesizes
/// per-case encoding (SE-0295).
enum TradeMessage: Codable, Sendable {
    case hello(nickname: String, code: String)
    case offer(TradeItem)
    case offerWithdrawn
    case accept
    case reject(reason: String)
    /// Informational only — by the time Accepts are exchanged, both sides have already
    /// independently started committing, so receiving this doesn't trigger any action
    /// (see TradeSession.handle). The nonce is for log correlation.
    case commit(nonce: String)
    case commitAck(nonce: String)
}
