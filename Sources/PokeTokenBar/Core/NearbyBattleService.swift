import Foundation
@preconcurrency import MultipeerConnectivity

/// MultipeerConnectivity carries `BattleLink` between Macs: peer-to-peer Wi-Fi (the AirDrop radio) when
/// nothing else is shared, or the local network. It also handles discovery, invitations and encryption,
/// which raw CoreBluetooth would leave to us.
enum NearbyBattle {
    /// Bonjour service type; must match `NSBonjourServices` in the app's Info.plist.
    static let serviceType = "ptb-battle"
    static let versionKey = "v"
    static let invitationTimeout: TimeInterval = 30
}

struct NearbyTrainer: Identifiable, Equatable {
    let id: MCPeerID
    var name: String { id.displayName }
    let isCompatible: Bool
}

struct IncomingChallenge: Identifiable {
    let id = UUID()
    let trainer: String
    fileprivate let peer: MCPeerID
    fileprivate let respond: (Bool, MCSession?) -> Void
}

/// Sendable wrapper for MultipeerConnectivity values that only cross from its delegate queue to the main actor.
private struct Unchecked<Value>: @unchecked Sendable {
    let value: Value
}

/// One connected peer as a `BattleTransport`.
@MainActor
final class MultipeerTransport: BattleTransport {
    var onReceive: ((Data) -> Void)?
    var onDisconnect: (() -> Void)?
    private let session: MCSession
    private let peer: MCPeerID
    private var isOpen = true

    init(session: MCSession, peer: MCPeerID) {
        self.session = session
        self.peer = peer
    }

    func send(_ data: Data) throws {
        guard isOpen else { throw BattleLinkError.disconnected }
        try session.send(data, toPeers: [peer], with: .reliable)
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        session.disconnect()
    }

    fileprivate func received(_ data: Data) { if isOpen { onReceive?(data) } }

    fileprivate func peerDisconnected() {
        guard isOpen else { return }
        isOpen = false
        onDisconnect?()
    }
}

/// Discovery, challenges and the handshake for battles with nearby Macs.
@MainActor @Observable
final class NearbyBattleService {
    enum Status: Equatable {
        case idle
        case challenging(String)
        case connecting
        case failed(Failure)
    }
    enum Failure: Equatable { case declined, unavailable, incompatible, lost }

    static let shared = NearbyBattleService()

    private(set) var isVisible = false
    private(set) var trainers: [NearbyTrainer] = []
    private(set) var incoming: IncomingChallenge?
    private(set) var status: Status = .idle
    /// Called with every finished nearby battle, for the win/loss record.
    var onFinish: ((BattleSession.Outcome) -> Void)?
    /// Opens the battle window; set by the UI layer.
    var present: ((BattleSession, String) -> Void)?
    /// Asks the UI to show an incoming challenge while the popover may be closed.
    var announce: ((IncomingChallenge) -> Void)?

    private var trainerName = ""
    private var team: BattleTeam?
    private var language: AppLanguage = .en
    private var names: @MainActor (PokemonNameResource) -> [String: String]? = { _ in nil }

    private var peerID: MCPeerID?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var session: MCSession?
    private var transport: MultipeerTransport?
    private var sessionPeer: MCPeerID?
    private var isChallenger = false
    private let proxy = MultipeerProxy()

    init() { proxy.owner = self }

    var isBusy: Bool {
        switch status {
        case .challenging, .connecting: return true
        case .idle, .failed: return transport != nil
        }
    }

    /// Updates what we battle with; only used when a battle starts, so it can change while visible.
    func configure(trainer: String, team: BattleTeam?, language: AppLanguage,
                   names: @escaping @MainActor (PokemonNameResource) -> [String: String]?) {
        let sanitized = BattleTrainer.sanitized(trainer)
        let nameChanged = sanitized != trainerName
        trainerName = sanitized.isEmpty ? BattleTrainer.defaultName() : sanitized
        self.team = team
        self.language = language
        self.names = names
        if nameChanged, isVisible { stop(); start() }
    }

    func start() {
        guard !isVisible else { return }
        let peer = MCPeerID(displayName: trainerName.isEmpty ? BattleTrainer.defaultName() : trainerName)
        let info = [NearbyBattle.versionKey: String(BattleWireMessage.protocolVersion)]
        let advertiser = MCNearbyServiceAdvertiser(peer: peer, discoveryInfo: info, serviceType: NearbyBattle.serviceType)
        let browser = MCNearbyServiceBrowser(peer: peer, serviceType: NearbyBattle.serviceType)
        advertiser.delegate = proxy
        browser.delegate = proxy
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
        peerID = peer
        self.advertiser = advertiser
        self.browser = browser
        isVisible = true
        if case .failed = status { status = .idle }
    }

    func stop() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        advertiser = nil
        browser = nil
        trainers = []
        declineIncoming()
        isVisible = false
        if transport == nil { tearDownSession() }
    }

    func challenge(_ trainer: NearbyTrainer) {
        guard let browser, let peerID, !isBusy, trainer.isCompatible else { return }
        let session = makeSession(peerID)
        isChallenger = true
        sessionPeer = trainer.id
        status = .challenging(trainer.name)
        let context = try? BattleWireMessage.hello(protocolVersion: BattleWireMessage.protocolVersion,
                                                   trainer: trainerName).encoded()
        browser.invitePeer(trainer.id, to: session, withContext: context, timeout: NearbyBattle.invitationTimeout)
    }

    func accept() {
        guard let incoming, let peerID else { return }
        self.incoming = nil
        let session = makeSession(peerID)
        isChallenger = false
        sessionPeer = incoming.peer
        status = .connecting
        incoming.respond(true, session)
    }

    func declineIncoming() {
        guard let incoming else { return }
        self.incoming = nil
        incoming.respond(false, nil)
    }

    func dismissFailure() { if case .failed = status { status = .idle } }

    // MARK: Delegate events (main actor)

    func found(_ peer: MCPeerID, info: [String: String]?) {
        guard peer != peerID else { return }
        let compatible = info?[NearbyBattle.versionKey] == String(BattleWireMessage.protocolVersion)
        trainers.removeAll { $0.id == peer }
        trainers.append(NearbyTrainer(id: peer, isCompatible: compatible))
        trainers.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func lost(_ peer: MCPeerID) {
        trainers.removeAll { $0.id == peer }
    }

    func invited(by peer: MCPeerID, context: Data?, respond: @escaping (Bool, MCSession?) -> Void) {
        guard Self.invitationIsAcceptable(context: context, isVisible: isVisible, isBusy: isBusy,
                                          hasIncoming: incoming != nil, hasTeam: team != nil) else {
            respond(false, nil)
            return
        }
        let challenge = IncomingChallenge(trainer: BattleTrainer.sanitized(peer.displayName), peer: peer, respond: respond)
        incoming = challenge
        announce?(challenge)
    }

    /// One battle at a time, only with a ready team, and only from a peer speaking our protocol version.
    static func invitationIsAcceptable(context: Data?, isVisible: Bool, isBusy: Bool, hasIncoming: Bool,
                                       hasTeam: Bool) -> Bool {
        guard isVisible, !isBusy, !hasIncoming, hasTeam, let context,
              case .hello(let version, _) = try? BattleWireMessage.decode(context) else { return false }
        return version == BattleWireMessage.protocolVersion
    }

    func peer(_ peer: MCPeerID, changed state: MCSessionState, in session: MCSession) {
        guard session === self.session, peer == sessionPeer else { return }
        switch state {
        case .connected:
            guard transport == nil else { return }
            status = .connecting
            let transport = MultipeerTransport(session: session, peer: peer)
            self.transport = transport
            Task { await self.beginBattle(over: transport) }
        case .notConnected:
            if let transport {
                transport.peerDisconnected()
            } else {
                // The invitation was declined, timed out, or the connection never came up.
                status = isChallenger ? .failed(.declined) : .failed(.lost)
                tearDownSession()
            }
        case .connecting:
            break
        @unknown default:
            break
        }
    }

    func received(_ data: Data, from peer: MCPeerID, in session: MCSession) {
        guard session === self.session, peer == sessionPeer else { return }
        transport?.received(data)
    }

    func discoveryFailed() {
        status = .failed(.unavailable)
    }

    // MARK: Battle

    private func beginBattle(over transport: MultipeerTransport) async {
        guard let team else { return finishSession(.lost) }
        let link = BattleLink(transport: transport)
        do {
            let match = try await BattleHandshake.run(link, isChallenger: isChallenger, trainer: trainerName,
                                                      team: team, nonce: UInt64.random(in: 1...UInt64.max))
            await BattleNamePrefetch.load([match.myTeam, match.opponentTeam])
            let session = BattleSession(myTeam: match.myTeam, opponentTeam: match.opponentTeam, seed: match.seed,
                                        opponent: NetworkOpponent(link: link), language: language,
                                        mySide: match.mySide, opponentName: match.opponentName,
                                        turnTimeLimit: .seconds(60), names: names)
            link.onInterrupt = { [weak session] error in session?.opponentInterrupted(error) }
            session.onFinish = { [weak self] outcome in
                self?.onFinish?(outcome)
                self?.finishSession(nil)
            }
            status = .idle
            present?(session, match.opponentName)
        } catch {
            AppLog.write("nearby battle handshake failed: \(error)")
            link.close()
            if case .incompatibleVersion = error as? BattleLinkError {
                finishSession(.incompatible)
            } else {
                finishSession(.lost)
            }
        }
    }

    /// Closing the battle window ends the connection too.
    func battleWindowClosed() {
        finishSession(nil)
    }

    private func finishSession(_ failure: Failure?) {
        tearDownSession()
        status = failure.map(Status.failed) ?? .idle
    }

    private func makeSession(_ peer: MCPeerID) -> MCSession {
        tearDownSession()
        let session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = proxy
        self.session = session
        return session
    }

    private func tearDownSession() {
        transport?.close()
        transport = nil
        session?.disconnect()
        session?.delegate = nil
        session = nil
        sessionPeer = nil
    }
}

/// MultipeerConnectivity calls its delegates on private queues; this forwards everything to the main actor.
private final class MultipeerProxy: NSObject, MCSessionDelegate, MCNearbyServiceAdvertiserDelegate,
                                    MCNearbyServiceBrowserDelegate, @unchecked Sendable {
    weak var owner: NearbyBattleService?

    /// The main queue, not `Task { @MainActor }`: tasks carry no ordering guarantee, and lockstep
    /// breaks if the peer's hello, team and moves are handled out of order.
    private func onMain(_ work: @escaping @MainActor (NearbyBattleService) -> Void) {
        let box = Unchecked(value: work)
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let owner = self?.owner else { return }
                box.value(owner)
            }
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        let box = Unchecked(value: (peerID, info))
        onMain { $0.found(box.value.0, info: box.value.1) }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        let box = Unchecked(value: peerID)
        onMain { $0.lost(box.value) }
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        onMain { $0.discoveryFailed() }
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        let box = Unchecked(value: (peerID, context, invitationHandler))
        onMain { $0.invited(by: box.value.0, context: box.value.1, respond: box.value.2) }
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        onMain { $0.discoveryFailed() }
    }

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let box = Unchecked(value: (peerID, session))
        onMain { $0.peer(box.value.0, changed: state, in: box.value.1) }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        let box = Unchecked(value: (peerID, session))
        onMain { $0.received(data, from: box.value.0, in: box.value.1) }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID,
                 with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID,
                 at localURL: URL?, withError error: Error?) {}
}

#if DEBUG
extension NearbyBattleService {
    /// Puts the lobby into a shown state without touching the network, for rendering screenshots.
    /// `trainer` must match what the view configures, or `configure` restarts real discovery.
    func stageForScreenshot(trainer: String, trainers names: [(String, compatible: Bool)], status: Status = .idle,
                            challengeFrom challenger: String? = nil) {
        trainerName = trainer
        isVisible = true
        trainers = names.map { NearbyTrainer(id: MCPeerID(displayName: $0.0), isCompatible: $0.compatible) }
        self.status = status
        incoming = challenger.map(IncomingChallengeStub.make)
    }
}

enum IncomingChallengeStub {
    static func make(_ trainer: String) -> IncomingChallenge {
        IncomingChallenge(trainer: trainer, peer: MCPeerID(displayName: trainer), respond: { _, _ in })
    }
}
#endif
