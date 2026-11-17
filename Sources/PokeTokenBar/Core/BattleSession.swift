import Foundation
import Network

/// Everything two Macs say to each other during a battle. One length-prefixed JSON object per message.
enum BattleMessage: Codable, Sendable, Equatable {
    /// Challenger → host: "battle me with this team".
    case hello(version: Int, player: BattlePlayer)
    /// Host → challenger: challenge refused, host busy, or version mismatch.
    case declined
    /// Host → challenger: the challenger's view after the simulator advanced.
    case snapshot(BattleSnapshot)
    /// Challenger → host: "move N" / "switch N".
    case choice(String)
    case forfeit
    /// Host → challenger: the last choice was illegal; choose again.
    case rejected(String)
    /// Scanner → lobby: "is a player here?" (VPNs carry no Bonjour). Answered with `.info`, then closed.
    case probe
    case info(name: String)
}

/// A LAN battle between two PokeTokenBar instances.
///
/// Both sides advertise and browse a Bonjour service. Whoever taps a peer becomes the challenger;
/// the challenged Mac is the host and runs the only `BattleEngine`. The challenger just sends
/// choices and renders the snapshots it gets back, so the two can never disagree about the state.
///
/// ponytail: plain TCP on the local network, no TLS or pairing. Fine for moves between friends on
/// one Wi-Fi; add `NWProtocolTLS` with a shared secret before this ever leaves the LAN.
@MainActor
@Observable
final class BattleSession {
    static let serviceType = "_ptbbattle._tcp"
    static let protocolVersion = 1
    /// Fixed so an address alone is enough to connect and a VPN subnet can be probed. A random port
    /// is the fallback when this one is taken (a second instance on the same Mac).
    static let defaultPort: NWEndpoint.Port = 47806
    /// A hello with three Pokémon is ~2 KB and a snapshot ~4 KB; anything near this is not ours.
    static let maxMessageSize = 256 * 1024
    static let maxLogLines = 300

    struct Peer: Identifiable, Equatable {
        let id: String
        let name: String
        let endpoint: NWEndpoint
    }

    enum Phase: Equatable {
        case idle
        case lobby
        case challenging(String)
        case incoming(String)
        case battle
    }

    enum Notice: Equatable {
        case declined, disconnected, engineFailed, networkFailed
    }

    private(set) var phase: Phase = .idle
    /// Bonjour results first, then players found by `scanVPN()`.
    var peers: [Peer] { browsed + scanned }
    private(set) var scanning = false
    private(set) var snapshot: BattleSnapshot?
    private(set) var log: [String] = []
    private(set) var notice: Notice?
    /// The simulator's explanation of why the last choice was refused (English, from Showdown).
    private(set) var rejection: String?
    /// The listener's port once it is up. Tests connect to it directly instead of through Bonjour.
    private(set) var port: NWEndpoint.Port?

    private let serviceName: String
    private let advertises: Bool
    private let engineDirectory: URL
    private var player = BattlePlayer(name: "", team: [])
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var browsed: [Peer] = []
    private var scanned: [Peer] = []
    private var probes: [NWConnection] = []
    private var isChallenger = false
    private var engine: BattleEngine?       // host only
    private var guest: BattlePlayer?        // host only: the pending/active challenger
    private var requestBeforeChoice: BattleSnapshot.Request?   // challenger only

    /// `advertises: false` keeps Bonjour (and the Local Network prompt) out of tests.
    init(advertises: Bool = true, engineDirectory: URL = BattleEnginePackages.defaultDirectory) {
        self.advertises = advertises
        self.engineDirectory = engineDirectory
        serviceName = String(format: "%04x", UInt16.random(in: 0...UInt16.max))
    }

    // MARK: Lobby

    func enterLobby(as player: BattlePlayer) {
        self.player = player
        notice = nil
        if listener == nil { startListener(on: advertises ? Self.defaultPort : .any) }
        if browser == nil, advertises { startBrowser() }
        if phase == .idle { phase = .lobby }
    }

    /// Leaves everything: called when the battle window closes.
    func stop() {
        dropConnection()
        listener?.cancel()
        browser?.cancel()
        listener = nil
        browser = nil
        port = nil
        browsed = []
        endScan()
        scanned = []
        clearBattle()
        phase = .idle
    }

    func challenge(_ peer: Peer) {
        challenge(endpoint: peer.endpoint, name: peer.name)
    }

    func challenge(endpoint: NWEndpoint, name: String) {
        guard phase == .lobby, connection == nil else { return }
        notice = nil
        isChallenger = true
        phase = .challenging(name)
        adopt(NWConnection(to: endpoint, using: Self.parameters))
    }

    /// Manual fallback for networks where Bonjour is filtered (guest Wi-Fi, VPN overlays):
    /// "host" or "host:port".
    @discardableResult
    func challenge(address: String) -> Bool {
        let parts = address.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), !parts[0].isEmpty,
              let port = parts.count == 1 ? Self.defaultPort : NWEndpoint.Port(String(parts[1])) else { return false }
        challenge(endpoint: .hostPort(host: NWEndpoint.Host(String(parts[0])), port: port), name: String(parts[0]))
        return true
    }

    /// What the other player types into "connect by address": every usable IPv4 of this Mac,
    /// with the port only when the fixed one was taken.
    var addresses: [String] {
        guard let port else { return [] }
        return Self.interfaceAddresses().map(\.ip).sorted()
            .map { port == Self.defaultPort ? $0 : "\($0):\(port.rawValue)" }
    }

    /// The other addresses of every VPN (point-to-point) subnet this Mac is on.
    /// ponytail: assumes a /24 around our own address, which covers WireGuard-style VPNs; read the
    /// routing table if someone needs wider subnets (Tailscale's 100.64/10 is not scannable anyway).
    static func vpnHosts() -> [String] {
        interfaceAddresses().filter(\.pointToPoint).flatMap { own -> [String] in
            let prefix = own.ip.split(separator: ".").dropLast().joined(separator: ".")
            return (1...254).map { "\(prefix).\($0)" }.filter { $0 != own.ip }
        }
    }

    /// One pass over the VPN subnets, started by the user: every address is asked once whether a
    /// player is waiting in a lobby there.
    func scanVPN() {
        scan(hosts: Self.vpnHosts(), port: Self.defaultPort)
    }

    func scan(hosts: [String], port: NWEndpoint.Port, timeout: Duration = .seconds(3)) {
        guard phase == .lobby, !scanning, !hosts.isEmpty else { return }
        scanning = true
        scanned = []
        hosts.forEach { probe($0, port: port) }
        let batch = probes
        Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard let self, self.probes.first === batch.first else { return }
            self.endScan()
        }
    }

    private func endScan() {
        probes.forEach { $0.cancel() }
        probes = []
        scanning = false
    }

    private func probe(_ host: String, port: NWEndpoint.Port) {
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: port)
        let connection = NWConnection(to: endpoint, using: Self.parameters)
        let question = Self.frame(.probe)
        probes.append(connection)
        connection.stateUpdateHandler = { [weak connection] state in
            switch state {
            case .ready: connection?.send(content: question, completion: .idempotent)
            case .failed, .waiting: connection?.cancel()
            default: break
            }
        }
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self, weak connection] header, _, _, _ in
            let length = header?.count == 4 ? header!.reduce(0) { $0 << 8 | Int($1) } : 0
            guard let connection, (1...1024).contains(length) else { return }
            connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self, weak connection] body, _, _, _ in
                MainActor.assumeIsolated {
                    connection?.cancel()
                    guard let self, self.scanning, let body,
                          case let .info(name)? = try? JSONDecoder().decode(BattleMessage.self, from: body),
                          !self.scanned.contains(where: { $0.id == host }) else { return }
                    self.scanned.append(Peer(id: host, name: "\(name.prefix(24)) (\(host))", endpoint: endpoint))
                    self.scanned.sort { $0.id < $1.id }
                }
            }
        }
        connection.start(queue: .main)
    }

    /// Non-loopback, non-link-local IPv4 addresses of the interfaces that are up.
    private static func interfaceAddresses() -> [(ip: String, pointToPoint: Bool)] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return [] }
        defer { freeifaddrs(list) }
        var found: [(ip: String, pointToPoint: Bool)] = []
        for interface in sequence(first: list, next: { $0?.pointee.ifa_next }) {
            guard let interface, let address = interface.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  interface.pointee.ifa_flags & UInt32(IFF_UP) != 0 else { continue }
            var name = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &name, socklen_t(name.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(cString: name)
            guard !ip.hasPrefix("127."), !ip.hasPrefix("169.254.") else { continue }
            found.append((ip, interface.pointee.ifa_flags & UInt32(IFF_POINTOPOINT) != 0))
        }
        return found
    }

    func cancelChallenge() {
        guard case .challenging = phase else { return }
        dropConnection()
        phase = .lobby
    }

    func accept() {
        guard case .incoming = phase, let guest else { return }
        do {
            let engine = try BattleEngine(directory: engineDirectory)
            let snapshots = try engine.start(host: player, guest: guest)
            self.engine = engine
            phase = .battle
            deliver(snapshots)
        } catch {
            AppLog.write("battle start failed: \(error)")
            closeAfterSending(.declined)
            notice = .engineFailed
            phase = .lobby
        }
    }

    func decline() {
        guard case .incoming = phase else { return }
        closeAfterSending(.declined)
        phase = .lobby
    }

    // MARK: Battle

    /// `choice` is "move N" or "switch N" with the 1-based slots from `snapshot.request`.
    func choose(_ choice: String) {
        guard phase == .battle, let snapshot, snapshot.request.kind != "wait" else { return }
        rejection = nil
        if let engine {
            do {
                deliver(try engine.choose(.p1, choice))
            } catch {
                rejection = Self.reason(error)
            }
        } else {
            // Lock the buttons until the host answers; `.rejected` puts the request back.
            requestBeforeChoice = snapshot.request
            self.snapshot?.request = .init(kind: "wait")
            send(.choice(choice))
        }
    }

    func forfeit() {
        guard phase == .battle, snapshot?.ended == false else { return }
        if let engine {
            if let snapshots = try? engine.forfeit(.p1) { deliver(snapshots) }
        } else {
            send(.forfeit)
        }
    }

    /// Back to the lobby from a running or finished battle.
    func leaveBattle() {
        guard phase == .battle else { return }
        dropConnection()
        clearBattle()
        phase = .lobby
    }

    // MARK: Networking

    private static var parameters: NWParameters { .tcp }

    /// Bonjour instance names are capped at 63 bytes; the suffix tells our own advertisement apart.
    private var advertisedName: String {
        var name = ""
        for character in player.name where name.utf8.count + String(character).utf8.count <= 48 {
            name.append(character)
        }
        return "\(name)#\(serviceName)"
    }

    private func startListener(on port: NWEndpoint.Port) {
        guard let listener = try? NWListener(using: Self.parameters, on: port) else {
            notice = .networkFailed
            return
        }
        if advertises {
            listener.service = NWListener.Service(name: advertisedName, type: Self.serviceType)
        }
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated { self?.incoming(connection) }
        }
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            MainActor.assumeIsolated {
                guard let self, let listener, self.listener === listener else { return }
                switch state {
                case .ready: self.port = listener.port
                case .failed:
                    listener.cancel()
                    self.listener = nil
                    // The fixed port is taken: any free one still works, the address just shows it.
                    if port == .any { self.notice = .networkFailed } else { self.startListener(on: .any) }
                default: break
                }
            }
        }
        self.listener = listener
        listener.start(queue: .main)
    }

    private func startBrowser() {
        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: .tcp)
        let ownName = advertisedName
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let peers = results.compactMap { result -> Peer? in
                guard case let .service(name, _, _, _) = result.endpoint, name != ownName else { return nil }
                let shown = name.split(separator: "#").dropLast().joined(separator: "#")
                return Peer(id: name, name: shown.isEmpty ? name : shown, endpoint: result.endpoint)
            }.sorted { $0.id < $1.id }
            MainActor.assumeIsolated { self?.browsed = peers }
        }
        self.browser = browser
        browser.start(queue: .main)
    }

    private func incoming(_ connection: NWConnection) {
        // One battle at a time: a second challenger is turned away.
        guard phase == .lobby, self.connection == nil else {
            connection.cancel()
            return
        }
        isChallenger = false
        adopt(connection)
    }

    private func adopt(_ connection: NWConnection) {
        self.connection = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            MainActor.assumeIsolated {
                guard let self, let connection, self.connection === connection else { return }
                switch state {
                case .ready:
                    if self.isChallenger {
                        self.send(.hello(version: Self.protocolVersion, player: self.player))
                    }
                case .failed, .cancelled, .waiting:
                    self.connectionLost()
                default:
                    break
                }
            }
        }
        connection.start(queue: .main)
        receive(on: connection)
    }

    /// Framing: a 4-byte big-endian length, then that many bytes of JSON.
    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self, weak connection] header, _, _, _ in
            MainActor.assumeIsolated {
                guard let self, let connection, self.connection === connection else { return }
                let length = header?.count == 4 ? header!.reduce(0) { $0 << 8 | Int($1) } : 0
                guard (1...Self.maxMessageSize).contains(length) else {
                    // Closed, failed, or not speaking our protocol.
                    self.connectionLost()
                    return
                }
                connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self, weak connection] body, _, _, _ in
                    MainActor.assumeIsolated {
                        guard let self, let connection, self.connection === connection else { return }
                        guard let body, body.count == length,
                              let message = try? JSONDecoder().decode(BattleMessage.self, from: body) else {
                            self.connectionLost()
                            return
                        }
                        self.handle(message)
                        if self.connection === connection { self.receive(on: connection) }
                    }
                }
            }
        }
    }

    private static func frame(_ message: BattleMessage) -> Data? {
        guard let body = try? JSONEncoder().encode(message), body.count <= maxMessageSize else { return nil }
        return withUnsafeBytes(of: UInt32(body.count).bigEndian) { Data($0) } + body
    }

    private func send(_ message: BattleMessage) {
        guard let connection, let data = Self.frame(message) else { return }
        connection.send(content: data, completion: .idempotent)
    }

    /// Sends a last word and hangs up once it is on the wire (a bare `cancel()` could drop it).
    private func closeAfterSending(_ message: BattleMessage) {
        guard let connection = detachConnection() else { return }
        guard let data = Self.frame(message) else { return connection.cancel() }
        connection.send(content: data, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func detachConnection() -> NWConnection? {
        let connection = self.connection
        self.connection = nil
        isChallenger = false
        engine = nil
        guest = nil
        requestBeforeChoice = nil
        return connection
    }

    private func dropConnection() {
        detachConnection()?.cancel()
    }

    private func connectionLost() {
        let wasChallenging: Bool
        if case .challenging = phase { wasChallenging = true } else { wasChallenging = false }
        dropConnection()
        // A finished battle stays on screen so the result can still be read.
        if phase == .battle, snapshot?.ended == true { return }
        if phase != .idle {
            clearBattle()
            phase = .lobby
            // A busy host hangs up on a challenger without a word; that reads as a refusal.
            notice = wasChallenging ? .declined : .disconnected
        }
    }

    private func clearBattle() {
        snapshot = nil
        log = []
        rejection = nil
    }

    // MARK: Protocol

    private func handle(_ message: BattleMessage) {
        switch message {
        case let .hello(version, player):
            guard !isChallenger, phase == .lobby, guest == nil else { return }
            guard version == Self.protocolVersion, !player.team.isEmpty else {
                closeAfterSending(.declined)
                return
            }
            let name = String(player.name.prefix(24))
            guest = BattlePlayer(name: name, team: Array(player.team.prefix(3)))
            phase = .incoming(name)
        case .declined:
            guard isChallenger else { return }
            dropConnection()
            clearBattle()
            phase = .lobby
            notice = .declined
        case let .snapshot(snapshot):
            guard isChallenger, phase != .lobby else { return }
            phase = .battle
            requestBeforeChoice = nil
            apply(snapshot)
        case let .choice(choice):
            guard let engine, phase == .battle else { return }
            do {
                deliver(try engine.choose(.p2, choice))
            } catch {
                send(.rejected(Self.reason(error)))
            }
        case .forfeit:
            guard let engine, phase == .battle, let snapshots = try? engine.forfeit(.p2) else { return }
            deliver(snapshots)
        case let .rejected(reason):
            guard isChallenger, let request = requestBeforeChoice else { return }
            requestBeforeChoice = nil
            snapshot?.request = request
            rejection = String(reason.prefix(200))
        case .probe:
            guard !isChallenger, phase == .lobby, guest == nil else { return }
            closeAfterSending(.info(name: player.name))
        case .info:
            break
        }
    }

    /// Host: show our side and send the challenger theirs.
    private func deliver(_ snapshots: [BattleEngine.SideID: BattleSnapshot]) {
        if let mine = snapshots[.p1] { apply(mine) }
        if let theirs = snapshots[.p2] { send(.snapshot(theirs)) }
    }

    private func apply(_ snapshot: BattleSnapshot) {
        self.snapshot = snapshot
        log.append(contentsOf: snapshot.log)
        if log.count > Self.maxLogLines { log.removeFirst(log.count - Self.maxLogLines) }
    }

    private static func reason(_ error: Error) -> String {
        if case let BattleEngineError.rejected(reason) = error { return reason }
        return "\(error)"
    }
}
