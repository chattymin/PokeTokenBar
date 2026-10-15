import Foundation
import MultipeerConnectivity

/// The default transport — automatically finds and connects to a peer on the same Wi-Fi/LAN.
/// **Support is limited to Wi-Fi/LAN — Bluetooth is on hold (unsupported, unverified).**
/// MultipeerConnectivity lets the framework choose the transport medium and gives no public API
/// to turn that off, so a Bluetooth PAN can opportunistically get used. That path is not
/// verified, though, and its behavior isn't guaranteed — defects in a Bluetooth-only environment
/// are out of scope, and the UI copy doesn't promise Bluetooth either.
/// The MCSession delegate is invoked on the framework's own queue, so this class is not
/// @MainActor — the consumer (TradeSession) hops itself with Task { @MainActor in … } (same
/// convention as NetworkReachabilityMonitor).
/// `discoveredPeers`/`advertiser`/`browser` are accessed concurrently from the delegate queue
/// (writes) and the caller's thread (reads), so they're protected with NSLock (Ruling R19) —
/// following the same lock convention as NetworkReachabilityMonitor: the lock is held only for
/// the short span of copying/swapping a value, and callbacks like onPeerFound/onPeerLost are
/// invoked after releasing it.
final class MultipeerTradeTransport: NSObject, TradeTransport, @unchecked Sendable {
    /// Bonjour service type — 1 to 15 chars, lowercase letters/digits/hyphens only (Apple spec).
    static let serviceType = "ptb-trade"
    /// The code key in the discoveryInfo dictionary — shared between startDiscovery and
    /// makeTradePeer so the value can't drift between them.
    static let discoveryInfoCodeKey = "code"

    var onPeerFound: (@Sendable (TradePeer) -> Void)?
    var onPeerLost: (@Sendable (String) -> Void)?
    var onConnected: (@Sendable () -> Void)?
    var onDisconnected: (@Sendable () -> Void)?
    var onMessageReceived: (@Sendable (TradeMessage) -> Void)?

    private let myPeerID: MCPeerID
    private let code: String
    /// When this was `lazy`, the first access raced between the caller's thread
    /// (connect/send/disconnect) and the framework queue (advertiser delegate) — unlike this
    /// class's other shared fields, it sat outside the lock. Creating it in init removes the
    /// race entirely.
    private let session: MCSession
    private let lock = NSLock()
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var discoveredPeers: [String: MCPeerID] = [:]
    /// The single peer we're currently trading with — MCSession supports multi-party
    /// connections, so this layer enforces the 1:1 constraint.
    private var partnerPeerID: MCPeerID?
    /// The peer I just invited — used only to detect a crossed invitation.
    private var invitedPeerID: MCPeerID?
    /// Increments per invitation — lets the expiry cleanup timer only clear the invitation it
    /// itself scheduled.
    private var inviteGeneration = 0
    /// Shares the same timeout with `invitePeer(timeout:)` and expiry cleanup — if the two drift
    /// apart, either `invitedPeerID` lingers after the invitation ended, or a still-live
    /// invitation gets cleared prematurely.
    private static let invitationTimeoutSeconds: TimeInterval = 15
    private let invitationQueue = DispatchQueue(label: "com.poketokenbar.trade-multipeer")

    /// The nickname is free text entered in Settings, so it can be empty or exceed 63 bytes —
    /// MCPeerID(displayName:) traps on such values, so it must be clamped before construction
    /// (Ruling R5).
    init(nickname: String, code: String) {
        let peerID = MCPeerID(displayName: Self.clampNickname(nickname, fallback: Host.current().localizedName ?? "PokeTokenBar"))
        myPeerID = peerID
        self.code = code
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        super.init()
        session.delegate = self
    }

    /// A total ordering that decides who accepts when invitations cross. The default nickname is
    /// the computer name, so two devices can share the same name — the nickname alone gives no
    /// ordering, so the per-device trade code is mixed in too.
    static func tiebreakKey(displayName: String, code: String?) -> String {
        "\(displayName)\u{0}\(code ?? "")"
    }

    /// Whether to accept an invitation — split out as a pure decision so it can be verified
    /// without framework callbacks.
    /// If a partner is already set, only accept from that partner (letting a third party in
    /// would make send() broadcast to two peers).
    /// If the invitation comes back from a peer I already invited, it's a crossed invitation —
    /// only the side with the larger key accepts, so the two connection attempts collapse to one.
    /// Codes differ per device, so the keys can't actually tie, but if they did, `>=` falls back
    /// to current behavior instead of a deadlock.
    static func shouldAccept(invitationFrom peer: String, partner: String?, invited: String?,
                             myKey: String, theirKey: String) -> Bool {
        if let partner { return partner == peer }
        guard invited == peer else { return true }
        return myKey >= theirKey
    }

    /// Whether an expired invitation is safe to clear. If an invitation that got no response
    /// lingers in `invitedPeerID`, tiebreak keeps rejecting that peer's later legitimate
    /// invitations, and no signal reaches the peer at all (today there's no recovery besides
    /// canceling and creating a fresh transport).
    /// If a newer invitation has since gone out, the generations don't match, so leave it to that
    /// invitation's own timer instead of touching it.
    /// If a partner is already set, `invitedPeerID` was already cleared in `.connected`.
    static func shouldClearExpiredInvitation(currentGeneration: Int, expiringGeneration: Int,
                                             hasPartner: Bool) -> Bool {
        currentGeneration == expiringGeneration && !hasPartner
    }

    /// discoveryInfo parsing is split out as a pure function — makes it unit-testable without a
    /// network stack.
    static func makeTradePeer(displayName: String, discoveryInfo: [String: String]?) -> TradePeer {
        TradePeer(id: displayName, nickname: displayName, code: discoveryInfo?[discoveryInfoCodeKey] ?? "????")
    }

    /// MCPeerID(displayName:) requires a non-empty name that's 63 bytes or fewer in UTF-8, and
    /// traps if that's violated. An empty value is replaced with the fallback, and a long value
    /// is truncated by byte budget (Korean/Japanese use multiple bytes per character, so
    /// truncating by character count could still exceed the budget).
    static func clampNickname(_ nickname: String, fallback: String) -> String {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        guard trimmed.utf8.count > 63 else { return trimmed }
        var truncated = trimmed
        while truncated.utf8.count > 63 {
            truncated.removeLast()
        }
        return truncated.isEmpty ? fallback : truncated
    }

    func startDiscovery() {
        let newAdvertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: [Self.discoveryInfoCodeKey: code],
                                                       serviceType: Self.serviceType)
        newAdvertiser.delegate = self

        let newBrowser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: Self.serviceType)
        newBrowser.delegate = self

        lock.lock()
        advertiser = newAdvertiser
        browser = newBrowser
        lock.unlock()

        newAdvertiser.startAdvertisingPeer()
        newBrowser.startBrowsingForPeers()
    }

    func stopDiscovery() {
        lock.lock()
        let currentAdvertiser = advertiser
        let currentBrowser = browser
        advertiser = nil
        browser = nil
        lock.unlock()

        currentAdvertiser?.stopAdvertisingPeer()
        currentBrowser?.stopBrowsingForPeers()
    }

    func connect(to peer: TradePeer) throws {
        lock.lock()
        let mcPeer = discoveredPeers[peer.id]
        let currentBrowser = browser
        let alreadyPaired = partnerPeerID != nil
        // The condition for actually sending the invitation must match the condition for setting
        // `invitedPeerID` — setting it on a path that throws would let an invitation that was
        // never sent block tiebreak.
        var pendingGeneration: Int?
        if let mcPeer, currentBrowser != nil, !alreadyPaired {
            invitedPeerID = mcPeer
            inviteGeneration += 1
            pendingGeneration = inviteGeneration
        }
        lock.unlock()

        // There's no dedicated case for "the peer is no longer in discoveredPeers", so notConnected is reused.
        guard let mcPeer, let currentBrowser, let pendingGeneration else { throw TradeTransportError.notConnected }
        // An invitation can expire with no signal at all (the peer never responds), so clean it
        // up ourselves on the same timeout.
        invitationQueue.asyncAfter(deadline: .now() + Self.invitationTimeoutSeconds) { [weak self] in
            self?.clearInvitationIfExpired(generation: pendingGeneration)
        }
        // Send my code along for crossed-invitation tiebreaking — the receiving side determines
        // ordering from this value alone, without discoveryInfo.
        currentBrowser.invitePeer(mcPeer, to: session, withContext: Data(code.utf8),
                                  timeout: Self.invitationTimeoutSeconds)
    }

    private func clearInvitationIfExpired(generation: Int) {
        lock.lock()
        let expired = Self.shouldClearExpiredInvitation(currentGeneration: inviteGeneration,
                                                        expiringGeneration: generation,
                                                        hasPartner: partnerPeerID != nil)
        if expired { invitedPeerID = nil }
        lock.unlock()
    }

    func send(_ message: TradeMessage) throws {
        lock.lock()
        let partner = partnerPeerID
        lock.unlock()
        // Restrict the destination to the confirmed single partner rather than connectedPeers —
        // even if a third party lingers in the session, my offer/accept doesn't also go to them.
        guard let partner, session.connectedPeers.contains(partner) else { throw TradeTransportError.sendFailed }
        guard let data = try? JSONEncoder().encode(message) else { throw TradeTransportError.sendFailed }
        do {
            try session.send(data, toPeers: [partner], with: .reliable)
        } catch {
            throw TradeTransportError.sendFailed
        }
    }

    func disconnect() {
        lock.lock()
        partnerPeerID = nil
        invitedPeerID = nil
        lock.unlock()
        session.disconnect()
    }
}

extension MultipeerTradeTransport: MCSessionDelegate {
    /// Ignore state changes for a peer that isn't the trade partner — a third party leaving must
    /// not break an in-progress trade or reset the screen to the start.
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case .connected:
            lock.lock()
            if partnerPeerID == nil { partnerPeerID = peerID }
            if invitedPeerID == peerID { invitedPeerID = nil }
            let isPartner = partnerPeerID == peerID
            lock.unlock()
            guard isPartner else { return }
            onConnected?()
        case .notConnected:
            // The rejected side of a crossed invitation can drive .notConnected for a peerID that
            // is **already connected** — only treat it as a real disconnect when the framework
            // has actually dropped that peer (otherwise a live trade would get reset).
            let stillConnected = session.connectedPeers.contains(peerID)
            lock.lock()
            let isPartner = partnerPeerID == peerID
            if isPartner, !stillConnected { partnerPeerID = nil }
            if invitedPeerID == peerID, !stillConnected { invitedPeerID = nil }
            lock.unlock()
            guard isPartner, !stillConnected else { return }
            onDisconnected?()
        case .connecting: break
        @unknown default: break
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        lock.lock()
        let isPartner = partnerPeerID == peerID
        lock.unlock()
        guard isPartner else { return }
        guard let message = try? JSONDecoder().decode(TradeMessage.self, from: data) else {
            // One line to distinguish, in the logs, a message we couldn't decode due to a
            // version mismatch from "the peer simply never made an offer."
            AppLog.write("trade: undecodable multipeer message (\(data.count) bytes) from \(peerID.displayName)")
            return
        }
        onMessageReceived?(message)
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension MultipeerTradeTransport: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        lock.lock()
        discoveredPeers[peerID.displayName] = peerID
        lock.unlock()
        onPeerFound?(Self.makeTradePeer(displayName: peerID.displayName, discoveryInfo: info))
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        lock.lock()
        discoveredPeers.removeValue(forKey: peerID.displayName)
        lock.unlock()
        onPeerLost?(peerID.displayName)
    }
}

extension MultipeerTradeTransport: MCNearbyServiceAdvertiserDelegate {
    /// Only accept invitations within the bounds that keep the connection 1:1 (see
    /// `shouldAccept`) — identity verification itself is left to the human, via the
    /// nickname/code shown in the subsequent Hello message.
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        lock.lock()
        let partner = partnerPeerID?.displayName
        let invited = invitedPeerID?.displayName
        lock.unlock()

        let theirCode = context.flatMap { String(data: $0, encoding: .utf8) }
        let accepted = Self.shouldAccept(invitationFrom: peerID.displayName, partner: partner, invited: invited,
                                         myKey: Self.tiebreakKey(displayName: myPeerID.displayName, code: code),
                                         theirKey: Self.tiebreakKey(displayName: peerID.displayName, code: theirCode))
        invitationHandler(accepted, accepted ? session : nil)
    }
}
