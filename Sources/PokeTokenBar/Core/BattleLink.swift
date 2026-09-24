import CryptoKit
import Foundation

/// Everything two peers say to each other. Only choices travel after the handshake: both sides run the
/// same deterministic engine, and every choice carries a digest of the state it was made in.
enum BattleWireMessage: Codable, Sendable, Equatable {
    case hello(protocolVersion: Int, trainer: String)
    case team(BattleTeam)
    case nonce(UInt64)
    case action(turn: Int, action: BattleAction, digest: String)
    /// No digest: when both sides replace, each applies the two picks in its own order. The next
    /// action's digest covers the result.
    case replacement(turn: Int, index: Int)
    case forfeit

    static let protocolVersion = 1
    static let maxSize = 256 * 1024

    func encoded() throws -> Data { try JSONEncoder().encode(self) }

    static func decode(_ data: Data) throws -> BattleWireMessage {
        guard data.count <= maxSize else { throw BattleLinkError.protocolViolation }
        return try JSONDecoder().decode(BattleWireMessage.self, from: data)
    }
}

enum BattleLinkError: Error, Equatable, Sendable {
    /// The peer is gone: closed the app, walked out of range, or stopped answering.
    case disconnected
    case timedOut
    case peerForfeited
    /// Nobody's fault as far as we can tell, so no winner: the states diverged or a message made no sense.
    case desync
    case protocolViolation
    case incompatibleVersion(Int)

    var abortsWithoutWinner: Bool {
        switch self {
        case .desync, .protocolViolation, .incompatibleVersion: return true
        case .disconnected, .timedOut, .peerForfeited: return false
        }
    }
}

extension BattleState {
    /// Sorted-key JSON of the full state, including the RNG, so any divergence changes the digest.
    var digest: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = (try? encoder.encode(self)) ?? Data()
        return SHA256.hash(data: data).prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}

/// A connected, ordered, reliable pipe to one peer.
@MainActor
protocol BattleTransport: AnyObject {
    var onReceive: ((Data) -> Void)? { get set }
    var onDisconnect: (() -> Void)? { get set }
    func send(_ data: Data) throws
    func close()
}

/// In-process pair for tests and for exercising the full protocol without a network.
@MainActor
final class LoopbackTransport: BattleTransport {
    var onReceive: ((Data) -> Void)?
    var onDisconnect: (() -> Void)?
    private weak var peer: LoopbackTransport?
    private var isOpen = true

    static func pair() -> (LoopbackTransport, LoopbackTransport) {
        let a = LoopbackTransport(), b = LoopbackTransport()
        a.peer = b
        b.peer = a
        return (a, b)
    }

    /// Delivered later on the main queue, which keeps order — like a real transport, and unlike `Task`.
    func send(_ data: Data) throws {
        guard isOpen, let peer, peer.isOpen else { throw BattleLinkError.disconnected }
        let box = UncheckedPeer(peer: peer)
        DispatchQueue.main.async { MainActor.assumeIsolated { box.peer.onReceive?(data) } }
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        guard let peer else { return }
        let box = UncheckedPeer(peer: peer)
        DispatchQueue.main.async { MainActor.assumeIsolated { box.peer.closeFromPeer() } }
    }

    private func closeFromPeer() {
        guard isOpen else { return }
        isOpen = false
        onDisconnect?()
    }
}

private struct UncheckedPeer: @unchecked Sendable {
    let peer: LoopbackTransport
}

/// Buffers messages that arrive before anyone asks for them; one waiter at a time, each with its own timeout.
@MainActor
final class BattleMailbox {
    private var buffer: [BattleWireMessage] = []
    private var waiter: (id: Int, continuation: CheckedContinuation<BattleWireMessage, Error>)?
    private var nextID = 0
    private(set) var closedWith: BattleLinkError?

    func deliver(_ message: BattleWireMessage) {
        guard closedWith == nil else { return }
        if let waiter {
            self.waiter = nil
            waiter.continuation.resume(returning: message)
        } else {
            buffer.append(message)
        }
    }

    func close(_ error: BattleLinkError) {
        guard closedWith == nil else { return }
        closedWith = error
        buffer.removeAll()
        if let waiter {
            self.waiter = nil
            waiter.continuation.resume(throwing: error)
        }
    }

    func next(timeout: Duration) async throws -> BattleWireMessage {
        if !buffer.isEmpty { return buffer.removeFirst() }
        if let closedWith { throw closedWith }
        nextID += 1
        let id = nextID
        return try await withCheckedThrowingContinuation { continuation in
            waiter = (id, continuation)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: timeout)
                self?.expire(id)
            }
        }
    }

    private func expire(_ id: Int) {
        guard let waiter, waiter.id == id else { return }
        self.waiter = nil
        waiter.continuation.resume(throwing: BattleLinkError.timedOut)
    }
}

/// One battle's worth of conversation with a peer, on top of any transport.
@MainActor
final class BattleLink {
    let transport: any BattleTransport
    let mailbox = BattleMailbox()
    /// Fires once when the peer forfeits or disappears, so a player who is still thinking hears it at once.
    var onInterrupt: ((BattleLinkError) -> Void)?

    init(transport: any BattleTransport) {
        self.transport = transport
        transport.onReceive = { [weak self] data in self?.receive(data) }
        transport.onDisconnect = { [weak self] in self?.interrupt(.disconnected) }
    }

    func send(_ message: BattleWireMessage) throws {
        guard mailbox.closedWith == nil else { throw mailbox.closedWith ?? .disconnected }
        try transport.send(try message.encoded())
    }

    func next(timeout: Duration) async throws -> BattleWireMessage {
        try await mailbox.next(timeout: timeout)
    }

    func close() {
        mailbox.close(.disconnected)
        transport.close()
    }

    private func receive(_ data: Data) {
        guard let message = try? BattleWireMessage.decode(data) else { return interrupt(.protocolViolation) }
        if message == .forfeit { return interrupt(.peerForfeited) }
        mailbox.deliver(message)
    }

    private func interrupt(_ error: BattleLinkError) {
        guard mailbox.closedWith == nil else { return }
        mailbox.close(error)
        onInterrupt?(error)
    }
}

/// What both sides agree on before turn one.
struct BattleMatch: Sendable, Equatable {
    let mySide: BattleSide
    let myTeam: BattleTeam
    let opponentTeam: BattleTeam
    let opponentName: String
    let seed: UInt64
}

enum BattleHandshake {
    static let timeout: Duration = .seconds(20)

    /// The challenger plays side `.a` on both machines; the seed mixes both nonces in that fixed order.
    /// Not tamper-proof — a peer could wait for our nonce before sending its own — which is acceptable
    /// because nothing is at stake in a battle.
    @MainActor
    static func run(_ link: BattleLink, isChallenger: Bool, trainer: String, team: BattleTeam,
                    nonce: UInt64) async throws -> BattleMatch {
        try link.send(.hello(protocolVersion: BattleWireMessage.protocolVersion, trainer: trainer))
        try link.send(.team(team))
        try link.send(.nonce(nonce))

        guard case .hello(let version, let peerName) = try await link.next(timeout: timeout) else {
            throw BattleLinkError.protocolViolation
        }
        guard version == BattleWireMessage.protocolVersion else { throw BattleLinkError.incompatibleVersion(version) }
        guard case .team(let peerTeam) = try await link.next(timeout: timeout) else { throw BattleLinkError.protocolViolation }
        guard case .nonce(let peerNonce) = try await link.next(timeout: timeout) else { throw BattleLinkError.protocolViolation }

        let (first, second) = isChallenger ? (nonce, peerNonce) : (peerNonce, nonce)
        var mixer = BattleRNG(seed: first ^ (second &* 0x9E37_79B9_7F4A_7C15))
        return BattleMatch(mySide: isChallenger ? .a : .b, myTeam: team, opponentTeam: peerTeam,
                           opponentName: String(peerName.prefix(BattleTrainer.maxNameLength)), seed: mixer.next())
    }
}

enum BattleTrainer {
    static let maxNameLength = 24
    static let defaultsKey = "battleTrainerName"

    static func sanitized(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { !$0.isNewline && !($0.unicodeScalars.first?.properties.generalCategory == .control) }
        return String(trimmed.prefix(maxNameLength))
    }

    /// Never the Mac's name or the user's real name: this is shown to strangers nearby.
    static func defaultName(random: UInt64 = UInt64.random(in: 0...UInt64.max)) -> String {
        "Trainer \(1000 + random % 9000)"
    }
}

/// The remote player, speaking through a `BattleLink`.
@MainActor
final class NetworkOpponent: BattleOpponent {
    let link: BattleLink
    /// Longer than the peer's own turn timer, so a slow but present player is not declared gone.
    let patience: Duration

    init(link: BattleLink, patience: Duration = .seconds(90)) {
        self.link = link
        self.patience = patience
    }

    func exchange(_ mine: BattleAction, in state: BattleState, side: BattleSide) async throws -> BattleAction {
        let digest = state.digest
        try link.send(.action(turn: state.turn, action: mine, digest: digest))
        guard case .action(let turn, let theirs, let theirDigest) = try await link.next(timeout: patience) else {
            throw BattleLinkError.protocolViolation
        }
        guard turn == state.turn, theirDigest == digest else { throw BattleLinkError.desync }
        return theirs
    }

    func sendReplacement(_ index: Int, in state: BattleState) async throws {
        try link.send(.replacement(turn: state.turn, index: index))
    }

    func replacement(in state: BattleState, side: BattleSide) async throws -> Int {
        guard case .replacement(let turn, let index) = try await link.next(timeout: patience) else {
            throw BattleLinkError.protocolViolation
        }
        guard turn == state.turn else { throw BattleLinkError.desync }
        return index
    }

    func notifyForfeit() { try? link.send(.forfeit) }
    func close() { link.close() }
}
