import Foundation

/// The trade protocol state machine — manages the Offer→Accept→Commit sequence independent of
/// the transport layer. This class does not perform the actual state application (backup+apply)
/// itself — whoever receives the `onReadyToCommit` callback (the CompanionStore consumer) must
/// call `confirmLocalCommit()` after finishing the apply for the session to complete.
@MainActor
final class TradeSession {
    private let transport: any TradeTransport
    /// The store that reads trade identity (nickname/code) — same injection convention as
    /// UsageStore/CompanionStore. If a test doesn't pass an isolated suite, simply sending hello
    /// will generate a tradeCode in the real user domain.
    private let defaults: UserDefaults
    private let sessionID = UUID().uuidString

    private(set) var peerIdentity: (nickname: String, code: String)?
    private(set) var myOffer: TradeItem?
    private(set) var theirOffer: TradeItem?
    private var myAcceptSent = false
    /// Observable session state at the same level as `theirOffer` — "has the peer's accept
    /// arrived" is a condition that gates whether we can commit, so it must be readable from
    /// outside.
    private(set) var theirAcceptReceived = false
    private var committed = false
    private var localCommitAckSent = false
    private var remoteCommitAckReceived = false
    private var completed = false

    var onPeerIdentified: (((nickname: String, code: String)) -> Void)?
    var onOffersReady: ((_ mine: TradeItem, _ theirs: TradeItem) -> Void)?
    /// The peer withdrew their offer — notify so the review screen stops showing an item that's
    /// no longer there.
    var onOfferWithdrawn: (() -> Void)?
    var onReadyToCommit: ((_ received: TradeItem) -> Void)?
    var onRejected: ((String) -> Void)?
    var onDisconnected: (() -> Void)?
    var onCompleted: (() -> Void)?

    init(transport: any TradeTransport, defaults: UserDefaults = .standard) {
        self.transport = transport
        self.defaults = defaults
        transport.onConnected = { [weak self] in
            Task { @MainActor [weak self] in self?.sendHello() }
        }
        transport.onMessageReceived = { [weak self] message in
            Task { @MainActor [weak self] in self?.handle(message) }
        }
        transport.onDisconnected = { [weak self] in
            Task { @MainActor [weak self] in self?.onDisconnected?() }
        }
    }

    private func sendHello() {
        try? transport.send(.hello(nickname: TradeIdentity.nickname(defaults: defaults),
                                   code: TradeIdentity.code(defaults: defaults)))
    }

    func proposeOffer(_ item: TradeItem) {
        myOffer = item
        // If the offer changes, any Accept for the previous review pair is void on both sides —
        // neither the Accept I sent nor the one the peer sent was consent for this new pair, so
        // clear both.
        invalidateAcceptsBeforeCommit()
        try? transport.send(.offer(item))
        notifyIfBothOffersReady()
    }

    func withdrawOffer() {
        myOffer = nil
        invalidateAcceptsBeforeCommit()
        try? transport.send(.offerWithdrawn)
    }

    func accept() {
        guard !myAcceptSent else { return }
        do {
            try transport.send(.accept)
            myAcceptSent = true
            commitIfBothAccepted()
        } catch {
            // Don't set the flag if the send fails — leaves accept() retryable.
        }
    }

    func reject(reason: String) {
        try? transport.send(.reject(reason: reason))
        transport.disconnect()
    }

    /// Call this after finishing the actual state application (CompanionStore.applyTradeCommit)
    /// triggered by `onReadyToCommit`.
    func confirmLocalCommit() {
        do {
            try transport.send(.commitAck(nonce: sessionID))
            localCommitAckSent = true
            checkCompleted()
        } catch {
            // Don't advance to completed if the send fails — the UI stays in the "committing"
            // state, leaving room for reconnect/retry.
        }
    }

    func disconnect() {
        transport.disconnect()
    }

    private func handle(_ message: TradeMessage) {
        switch message {
        case .hello(let nickname, let code):
            peerIdentity = (nickname, code)
            onPeerIdentified?((nickname, code))
        case .offer(let item):
            theirOffer = item.sanitized()
            invalidateAcceptsBeforeCommit()
            notifyIfBothOffersReady()
        case .offerWithdrawn:
            theirOffer = nil
            invalidateAcceptsBeforeCommit()
            onOfferWithdrawn?()
        case .accept:
            theirAcceptReceived = true
            commitIfBothAccepted()
        case .reject(let reason):
            onRejected?(reason)
        case .commit:
            break   // Informational only — both sides already reach commitIfBothAccepted independently once Accepts are exchanged.
        case .commitAck:
            remoteCommitAckReceived = true
            checkCompleted()
        }
    }

    /// An Accept is consent for "this specific offer pair, right now" — before commit, if either
    /// side's offer changes, both Accept flags (the one I sent, the one I received from the
    /// peer) lose their basis for consent, so clear them together.
    private func invalidateAcceptsBeforeCommit() {
        guard !committed else { return }
        myAcceptSent = false
        theirAcceptReceived = false
    }

    private func notifyIfBothOffersReady() {
        guard let myOffer, let theirOffer else { return }
        onOffersReady?(myOffer, theirOffer)
    }

    private func commitIfBothAccepted() {
        guard myOffer != nil, myAcceptSent, theirAcceptReceived, !committed, let theirOffer else { return }
        committed = true
        try? transport.send(.commit(nonce: sessionID))
        onReadyToCommit?(theirOffer)
    }

    private func checkCompleted() {
        guard localCommitAckSent, remoteCommitAckReceived, !completed else { return }
        completed = true
        onCompleted?()
    }
}
