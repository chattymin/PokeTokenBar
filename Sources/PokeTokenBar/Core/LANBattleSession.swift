import Foundation
import Network
import Observation
import Darwin

/// A bounded protocol for one limited ruleset match on a trusted local network.
enum LANBattleMessage: Codable, Sendable {
    case hello(version: String, combatant: BattleCombatant)
    case start(version: String, seed: UInt64, first: BattleCombatant, second: BattleCombatant)
    case command(revision: Int, moveID: String)
    case resolved(revision: Int, firstMoveID: String, secondMoveID: String, snapshot: BattleState)
}

enum LANBattleProtocolError: Error { case invalidFrame, invalidMessage }

/// TCP is a byte stream: a four-byte big-endian length precedes each bounded JSON message.
enum LANBattleCodec {
    static let maximumPayload = 65_536

    static func encode(_ message: LANBattleMessage) throws -> Data {
        let payload = try JSONEncoder().encode(message)
        guard !payload.isEmpty, payload.count <= maximumPayload else { throw LANBattleProtocolError.invalidFrame }
        var length = UInt32(payload.count).bigEndian
        var result = Data(bytes: &length, count: 4)
        result.append(payload)
        return result
    }

    static func extract(from buffer: inout Data) throws -> [LANBattleMessage] {
        var messages: [LANBattleMessage] = []
        while buffer.count >= 4 {
            let length = buffer.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
            guard length > 0, length <= maximumPayload else { throw LANBattleProtocolError.invalidFrame }
            guard buffer.count >= 4 + length else { break }
            let payload = Data(buffer.dropFirst(4).prefix(length))
            messages.append(try JSONDecoder().decode(LANBattleMessage.self, from: payload))
            buffer.removeFirst(4 + length)
        }
        guard buffer.count <= maximumPayload + 4 else { throw LANBattleProtocolError.invalidFrame }
        return messages
    }
}

@MainActor @Observable
final class LANBattleSession {
    enum Status: Equatable { case idle, listening, connecting, waiting, playing, finished, failed }
    private(set) var status: Status = .idle
    private(set) var statusMessage: String?
    private(set) var battle: BattleState?
    private(set) var lastTurnEvents: [BattleEvent] = []
    private(set) var revision = 0
    private(set) var localSide = 0
    private(set) var hasSubmittedMove = false
    private(set) var listeningPort: UInt16 = 43821
    var localAddresses: [String] { Self.addresses() }
    static var protocolVersion: String { "lan-v3/rules-\(BattleState.rulesetVersion)" }

    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private var connection: NWConnection?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var buffer = Data()
    @ObservationIgnored private var localCombatant: BattleCombatant?
    @ObservationIgnored private var engine: BattleState?
    @ObservationIgnored private var hostMoveID: String?
    @ObservationIgnored private var guestMoveID: String?
    @ObservationIgnored private var timeout: Task<Void, Never>?
    @ObservationIgnored private let queue = DispatchQueue(label: "poketokenbar.lan-battle")

    func host(combatant: BattleCombatant, port: UInt16 = 43821) {
        disconnect()
        guard let endpoint = NWEndpoint.Port(rawValue: port), port > 0 else {
            fail("Invalid Pokémon or port."); return
        }
        localSide = 0; localCombatant = combatant; listeningPort = port
        do {
            let parameters = NWParameters.tcp
            parameters.includePeerToPeer = false
            let created = try NWListener(using: parameters, on: endpoint)
            listener = created; status = .listening
            let token = generation
            created.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token else { return }
                    if case .failed = state { self.fail("Cannot host on this port. Try another port.") }
                }
            }
            created.newConnectionHandler = { [weak self] peer in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token, self.connection == nil else { peer.cancel(); return }
                    self.listener?.cancel(); self.listener = nil
                    self.attach(peer, token: token)
                }
            }
            created.start(queue: queue)
        } catch { fail("Cannot host on this port. Try another port.") }
    }

    func join(host: String, port: UInt16 = 43821, combatant: BattleCombatant) {
        disconnect()
        let address = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty, address.count <= 253,
              let endpoint = NWEndpoint.Port(rawValue: port), port > 0 else {
            fail("Enter a valid host address and port."); return
        }
        localSide = 1; localCombatant = combatant; status = .connecting
        attach(NWConnection(host: NWEndpoint.Host(address), port: endpoint, using: .tcp), token: generation)
    }

    func submit(moveID: String) {
        guard status == .playing, !hasSubmittedMove, let battle,
              Self.validChoice(moveID, side: localSide, state: battle) else { return }
        hasSubmittedMove = true
        if localSide == 0 { hostMoveID = moveID; resolveIfReady() }
        else { guestMoveID = moveID; send(.command(revision: revision, moveID: moveID)) }
    }

    func disconnect() {
        generation = UUID()
        timeout?.cancel(); timeout = nil
        listener?.cancel(); listener = nil
        connection?.cancel(); connection = nil
        buffer = Data(); localCombatant = nil; engine = nil; hostMoveID = nil; guestMoveID = nil
        battle = nil; lastTurnEvents = []; hasSubmittedMove = false; revision = 0
        status = .idle; statusMessage = nil
    }

    private func attach(_ peer: NWConnection, token: UUID) {
        connection = peer; armTimeout(token: token)
        peer.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                switch state {
                case .ready:
                    self.status = .waiting
                    if self.localSide == 1, let combatant = self.localCombatant {
                        self.send(.hello(version: Self.protocolVersion, combatant: combatant))
                    }
                    self.receive(peer, token: token)
                case .failed: self.fail("Connection failed. Check the address, Wi-Fi, and firewall.")
                case .cancelled: break
                default: break
                }
            }
        }
        peer.start(queue: queue)
    }

    private func receive(_ peer: NWConnection, token: UUID) {
        peer.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, complete, error in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                do {
                    if let data {
                        self.buffer.append(data)
                        for message in try LANBattleCodec.extract(from: &self.buffer) { try self.handle(message) }
                    }
                    guard self.generation == token else { return }
                    if complete || error != nil { self.fail("Your friend disconnected. Create or join a new room.") }
                    else { self.receive(peer, token: token) }
                } catch { self.fail("Incompatible or invalid battle data. Use the same app version.") }
            }
        }
    }

    private func handle(_ message: LANBattleMessage) throws {
        switch message {
        case let .hello(version, guest):
            guard localSide == 0, engine == nil, version == Self.protocolVersion,
                  let localCombatant else { throw LANBattleProtocolError.invalidMessage }
            let seed = UInt64.random(in: .min ... .max)
            let state = try BattleState(first: localCombatant, second: guest, seed: seed)
            engine = state; battle = state; revision = 1
            timeout?.cancel(); timeout = nil
            status = state.isFinished ? .finished : .playing
            send(.start(version: Self.protocolVersion, seed: seed, first: localCombatant, second: guest))
        case let .start(version, seed, first, second):
            guard localSide == 1, engine == nil, version == Self.protocolVersion,
                  let localCombatant, second == localCombatant else { throw LANBattleProtocolError.invalidMessage }
            let state = try BattleState(first: first, second: second, seed: seed)
            engine = state; battle = state; revision = 1
            timeout?.cancel(); timeout = nil
            status = state.isFinished ? .finished : .playing
        case let .command(sentRevision, moveID):
            guard localSide == 0, status == .playing, sentRevision == revision,
                  guestMoveID == nil, let battle,
                  Self.validChoice(moveID, side: 1, state: battle) else { throw LANBattleProtocolError.invalidMessage }
            guestMoveID = moveID; resolveIfReady()
        case let .resolved(nextRevision, firstMoveID, secondMoveID, expected):
            guard localSide == 1, status == .playing, nextRevision == revision + 1,
                  hasSubmittedMove, guestMoveID == secondMoveID, var engine else { throw LANBattleProtocolError.invalidMessage }
            let events = try engine.resolve(firstMoveID: firstMoveID, secondMoveID: secondMoveID)
            guard engine == expected else { throw LANBattleProtocolError.invalidMessage }
            self.engine = engine; battle = engine; lastTurnEvents = events; revision = nextRevision
            guestMoveID = nil; hasSubmittedMove = false
            status = engine.isFinished ? .finished : .playing
        }
    }

    private func resolveIfReady() {
        guard var engine, let first = hostMoveID, let second = guestMoveID else { return }
        do {
            let events = try engine.resolve(firstMoveID: first, secondMoveID: second)
            battle = engine; revision += 1
            lastTurnEvents = events
            hostMoveID = nil; guestMoveID = nil; hasSubmittedMove = false
            status = engine.isFinished ? .finished : .playing
            self.engine = engine
            send(.resolved(revision: revision, firstMoveID: first, secondMoveID: second, snapshot: engine))
        } catch { fail("The battle could not continue. Create a new room.") }
    }

    private func send(_ message: LANBattleMessage) {
        guard let connection else { return }
        do {
            let data = try LANBattleCodec.encode(message); let token = generation
            connection.send(content: data, completion: .contentProcessed { [weak self] error in
                guard error != nil else { return }
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token else { return }
                    self.fail("Could not send battle data. Reconnect to your friend.")
                }
            })
        } catch { fail("Battle data is too large or invalid.") }
    }

    private func armTimeout(token: UUID) {
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled, let self, self.generation == token, self.battle == nil else { return }
            self.fail("Connection timed out. Check the address, Wi-Fi, and firewall.")
        }
    }

    private func fail(_ message: String) { disconnect(); status = .failed; statusMessage = message }

    static func validChoice(_ moveID: String, side: Int, state: BattleState) -> Bool {
        guard !state.isFinished, state.fighters.indices.contains(side) else { return false }
        return state.fighters[side].combatant.moves.contains { $0.id == moveID }
    }

    private static func addresses() -> [String] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return [] }
        defer { freeifaddrs(list) }
        var result: [String] = []
        var current = list
        while let interface = current {
            defer { current = interface.pointee.ifa_next }
            guard let address = interface.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  (interface.pointee.ifa_flags & UInt32(IFF_LOOPBACK)) == 0,
                  (interface.pointee.ifa_flags & UInt32(IFF_UP)) != 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                let bytes = host.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
                result.append(String(decoding: bytes, as: UTF8.self))
            }
        }
        return Array(Set(result)).sorted()
    }
}
