import AppKit
import SwiftUI

/// The popover's "Trade" tab — identity display, peer discovery (automatic with manual fallback),
/// offer selection, acceptance, and commit outcome, all handled in a single screen.
@MainActor
struct TradeView: View {
    let store: CompanionStore
    /// Signals that the popover shouldn't close on outside clicks while a trade is in progress —
    /// if it closes, `onDisappear` tears down the session and the trade is lost (see the comment
    /// on `PopoverNavigation.tradeSessionActive`).
    @Environment(PopoverNavigation.self) private var navigation

    /// The manual fallback listener's state. Collapsing "still preparing" and "failed to create"
    /// into a single `String?` would show a failure message during the few milliseconds it's
    /// still preparing.
    private enum ManualListener {
        case preparing
        case ready(code: String)
        case unavailable
    }

    /// `TradeItem` isn't Equatable, so this enum can't be Equatable either — check the phase only
    /// with `if case`/`switch` pattern matching, never `==`.
    private enum Phase {
        case idle
        case searching
        case manualFallback(listener: ManualListener, connecting: Bool)
        case pickingOffer
        case waitingForPeerOffer
        case reviewingProposal(mine: TradeItem, theirs: TradeItem)
        case waitingForPeerAccept
        /// The local commit (backup + state update) is done and we're waiting for the peer's
        /// commitAck — if the connection drops here, the irreversible change has already
        /// happened, so we go to `.uncertain`.
        case committing
        case completed
        case rejected
        /// The apply itself was aborted because the backup failed — nothing changed, so this is
        /// distinct from `.uncertain`, whose purpose is showing backup guidance.
        case commitFailed
        case uncertain
    }

    /// How long to wait before giving up on automatic discovery and switching to manual code exchange.
    private static let discoveryTimeoutNanoseconds: UInt64 = 10_000_000_000

    @State private var phase: Phase = .idle
    @State private var multipeerTransport: MultipeerTradeTransport?
    @State private var manualTransport: ManualTradeTransport?
    @State private var session: TradeSession?
    @State private var discoveredPeers: [TradePeer] = []
    @State private var connectedPeer: TradePeer?
    @State private var manualCodeInput = ""
    @State private var manualCodeInvalid = false
    @State private var discoveryTimeout: Task<Void, Never>?
    @State private var lastBackupURL: URL?
    @State private var connectFailed = false

    private var l: L { store.l }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            identityHeader
            Divider()
            phaseContent
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Switching tabs or closing the popover destroys this view, but the closures startSession
        // planted hold the @State boxes through a copy of the view struct, so the session and
        // transport survive — the peer's accept can be received with no screen present, running
        // all the way through applyTradeCommit (silently changing the save), with the backup
        // location recorded in the now-discarded box.
        .onDisappear { teardownConnection() }
    }

    // MARK: Identity header

    private var identityHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(TradeIdentity.nickname()).font(.headline)
            Text("\(l.tradeMyCode): \(TradeIdentity.code())")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            if let connectedPeer {
                Text("\(l.tradeConnectedTo): \(connectedPeer.nickname) (\(connectedPeer.code))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Per-phase body

    @ViewBuilder
    private var phaseContent: some View {
        switch phase {
        case .idle:
            Button(l.tradeFindPeers) { startAutomaticDiscovery() }
        case .searching:
            searchingContent
        case .manualFallback(let listener, let connecting):
            manualFallbackContent(listener: listener, connecting: connecting)
        case .pickingOffer:
            offerPicker
        case .waitingForPeerOffer:
            waitingWithRepick(l.tradeWaitingForPeerOffer)
        case .reviewingProposal(let mine, let theirs):
            TradeProposalPanel(
                myOffer: mine,
                theirOffer: theirs,
                overwriteWarning: store.tradeOverwriteWarning(forReceiving: theirs),
                store: store,
                l: l,
                onAccept: { acceptProposal() },
                onReject: { rejectProposal() })
        case .waitingForPeerAccept:
            waitingWithRepick(l.tradeWaitingForPeerAccept)
        case .committing:
            VStack(alignment: .leading, spacing: 8) {
                waitingRow(l.tradeWaitingForPeerConfirm)
                backupHint
                Button(l.close) { closeFromCommitting() }
            }
        case .completed:
            outcomeContent(title: l.tradeCompleted, showsBackupHint: true)
        case .uncertain:
            outcomeContent(title: l.tradeUncertain, showsBackupHint: true)
        case .commitFailed:
            outcomeContent(title: l.tradeCommitFailed, showsBackupHint: false)
        case .rejected:
            outcomeContent(title: l.tradeRejectedByPeer, showsBackupHint: false)
        }
    }

    private var searchingContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            waitingRow(l.tradeSearching)
            ForEach(discoveredPeers) { peer in
                Button("\(peer.nickname) (\(peer.code))") { connect(to: peer) }
            }
            if connectFailed {
                Text(l.tradeConnectFailed)
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // If an invite expires without a response, the transport gives no signal at all, and
            // the automatic fallback timer backs off once it has found even one peer — so there
            // must be a manual way for the person to switch to a manual connection.
            Button(l.tradeSwitchToManual) { fallBackToManual() }
            Button(l.cancel) { resetToIdle() }
        }
    }

    private func manualFallbackContent(listener: ManualListener, connecting: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l.tradeAutoDiscoveryFailed)
                .font(.caption).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            switch listener {
            case .preparing:
                Text(l.tradeManualCodePreparing).font(.caption).foregroundStyle(.secondary)
            case .ready(let code):
                Text("\(l.tradeManualMyCode): \(code)")
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            case .unavailable:
                Text(l.tradeManualCodeUnavailable)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if connecting {
                // If the peer's address simply doesn't respond, the transport gives no signal at
                // all — don't declare failure, keep showing progress, but always leave a way back
                // to re-enter the code.
                waitingRow(l.tradeManualConnecting)
                Button(l.cancel) { cancelManualConnecting() }
            } else {
                TextField(l.tradeManualEnterCode, text: $manualCodeInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { connectManually() }
                if manualCodeInvalid {
                    Text(l.tradeManualCodeInvalid)
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    Button(l.tradeManualConnect) { connectManually() }
                    Button(l.cancel) { resetToIdle() }
                }
            }
        }
    }

    private var offerPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l.tradeSelectOffer).font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if let active = store.state.active {
                        offerRow(item: .activeMon(active), badge: l.dexRaising)
                    }
                    ForEach(store.tradeOfferableDexEntries) { entry in
                        offerRow(item: .dexEntry(entry), badge: nil)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 300)
            Button(l.cancel) { resetToIdle() }
        }
    }

    private func offerRow(item: TradeItem, badge: String?) -> some View {
        Button {
            propose(item)
        } label: {
            HStack(spacing: 6) {
                TradeItemRow(item: item, store: store, spriteSize: 24)
                if let badge {
                    Text(badge).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Text(l.rarityLabel(item.rarity)).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func waitingWithRepick(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            waitingRow(message)
            Button(l.tradeSelectOffer) { returnToOfferPicker() }
            Button(l.cancel) { resetToIdle() }
        }
    }

    private func outcomeContent(title: String, showsBackupHint: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.callout.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            if showsBackupHint { backupHint }
            Button(l.close) { resetToIdle() }
        }
    }

    private func waitingRow(_ message: String) -> some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text(message).font(.caption).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var backupHint: some View {
        if let lastBackupURL {
            VStack(alignment: .leading, spacing: 6) {
                Text(l.tradeBackupHint(fileName: lastBackupURL.lastPathComponent))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                // Open with this backup file selected, not just the folder — so it's unambiguous
                // which of several backups is the current one.
                Button(l.tradeOpenBackupFolder) {
                    NSWorkspace.shared.activateFileViewerSelecting([lastBackupURL])
                }
            }
        }
    }

    // MARK: Connection

    private func startAutomaticDiscovery() {
        navigation.tradeSessionActive = true
        let transport = MultipeerTradeTransport(nickname: TradeIdentity.nickname(), code: TradeIdentity.code())
        transport.onPeerFound = { peer in Task { @MainActor in addDiscoveredPeer(peer) } }
        transport.onPeerLost = { peerID in
            Task { @MainActor in discoveredPeers.removeAll { $0.id == peerID } }
        }
        multipeerTransport = transport
        // Create the session **before** connecting — even the side receiving the invite needs the
        // session already holding the transport's onConnected to exchange Hello messages. If it's
        // created after connecting, that side never identifies its peer.
        startSession(with: transport)
        transport.startDiscovery()
        phase = .searching
        discoveryTimeout = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.discoveryTimeoutNanoseconds)
            guard !Task.isCancelled, case .searching = phase, discoveredPeers.isEmpty else { return }
            transport.stopDiscovery()
            fallBackToManual()
        }
    }

    private func addDiscoveredPeer(_ peer: TradePeer) {
        guard !discoveredPeers.contains(where: { $0.id == peer.id }) else { return }
        discoveredPeers.append(peer)
    }

    /// Enters manual fallback. `startListening`'s completion fires synchronously when there's no
    /// local IPv4 address or listener creation fails, and otherwise fires exactly once,
    /// asynchronously, on the Network framework's callback queue — so the phase is set to
    /// `.preparing` first, before listening starts, so the result can update the phase whenever
    /// it actually arrives.
    private func fallBackToManual() {
        discoveryTimeout?.cancel()
        discoveryTimeout = nil
        releaseMultipeerTransport()
        discoveredPeers = []
        connectFailed = false
        let transport = ManualTradeTransport()
        manualTransport = transport
        startSession(with: transport)
        phase = .manualFallback(listener: .preparing, connecting: false)
        transport.startListening { code in
            Task { @MainActor in applyManualListening(code: code) }
        }
    }

    private func applyManualListening(code: String?) {
        guard case .manualFallback(_, let connecting) = phase else { return }
        phase = .manualFallback(listener: code.map { .ready(code: $0) } ?? .unavailable, connecting: connecting)
    }

    /// The discovery timeout isn't cancelled here — only in `onPeerIdentified`, once the
    /// connection is confirmed. Clearing the fallback path just from sending an invite would trap
    /// us in `.searching` if the invite never actually succeeds.
    private func connect(to peer: TradePeer) {
        guard let multipeerTransport else { return }
        do {
            try multipeerTransport.connect(to: peer)
            connectFailed = false
        } catch {
            // The peer is stale (already gone) or already trading with someone else — remove the
            // row and let the person know.
            discoveredPeers.removeAll { $0.id == peer.id }
            connectFailed = true
        }
    }

    private func connectManually() {
        guard let manualTransport, case .manualFallback(let listener, false) = phase else { return }
        let code = manualCodeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        do {
            try manualTransport.connectManually(code: code)
            manualCodeInvalid = false
            phase = .manualFallback(listener: listener, connecting: true)
        } catch {
            manualCodeInvalid = true
        }
    }

    /// Cancelling doesn't disconnect the transport — the listener is shared, so disconnecting
    /// would also kill our own connection code. Any pending connection gets replaced by the next
    /// `connectManually` inside `wire`.
    private func cancelManualConnecting() {
        guard case .manualFallback(let listener, true) = phase else { return }
        phase = .manualFallback(listener: listener, connecting: false)
    }

    // MARK: Session

    private func startSession(with transport: any TradeTransport) {
        // The fallback path swaps sessions — the old one must not keep firing callbacks here.
        releaseSession()
        let newSession = TradeSession(transport: transport)
        newSession.onPeerIdentified = { identity in
            connectedPeer = TradePeer(id: identity.code, nickname: identity.nickname, code: identity.code)
            switch phase {
            case .searching, .manualFallback:
                discoveryTimeout?.cancel()
                multipeerTransport?.stopDiscovery()
                phase = .pickingOffer
            default:
                break
            }
        }
        newSession.onOffersReady = { mine, theirs in
            // Whichever side's offer changes, the session invalidates both Accepts, so we go
            // back to the review phase. Offers arriving after commit are ignored — a trade
            // that's already been applied can't be accepted again.
            switch phase {
            case .committing, .completed, .uncertain, .commitFailed, .rejected:
                break
            default:
                phase = .reviewingProposal(mine: mine, theirs: theirs)
            }
        }
        newSession.onOfferWithdrawn = {
            // The review screen is a snapshot from the moment the offer arrived, so it keeps
            // promising an item the peer has withdrawn — that can't sit next to an irreversible
            // accept button, so we fall back to the waiting phase. Our own offer is left as is.
            if case .reviewingProposal = phase { phase = .waitingForPeerOffer }
        }
        newSession.onReadyToCommit = { [weak newSession] received in
            // `sending:` must always be our own local offer — passing in a value echoed back by
            // the peer would let it delete an arbitrary Pokédex entry without normalization
            // (per the `CompanionStore.applyTradeCommit` contract).
            // If the session is already gone, don't even **start** applying — stopping with
            // nothing changed is safer than applying the trade and then failing to send the ack
            // (the same direction as the backup-failure path below).
            guard let newSession, let myOffer = newSession.myOffer else { return }
            do {
                lastBackupURL = try store.applyTradeCommit(sending: myOffer, receiving: received)
            } catch {
                // The apply was aborted because we couldn't write the backup — we don't send
                // commitAck, so the peer also stays unconfirmed (a failure that leaves both
                // sides' local state unchanged, which is the safe direction).
                phase = .commitFailed
                newSession.disconnect()
                return
            }
            phase = .committing
            newSession.confirmLocalCommit()
        }
        newSession.onCompleted = { phase = .completed }
        newSession.onRejected = { _ in
            teardownConnection()
            phase = .rejected
        }
        newSession.onDisconnected = {
            switch phase {
            case .committing:
                phase = .uncertain   // The irreversible local change has already finished
            case .manualFallback(let listener, true):
                phase = .manualFallback(listener: listener, connecting: false)
            case .idle, .searching, .manualFallback, .completed, .uncertain, .commitFailed, .rejected:
                break
            default:
                resetToIdle()
            }
        }
        session = newSession
    }

    private func propose(_ item: TradeItem) {
        session?.proposeOffer(item)
        // If the peer's offer has already arrived, proposeOffer moves us to the review phase itself — don't overwrite that.
        if case .pickingOffer = phase { phase = .waitingForPeerOffer }
    }

    private func returnToOfferPicker() {
        session?.withdrawOffer()
        phase = .pickingOffer
    }

    private func acceptProposal() {
        session?.accept()
        // If the peer already accepted first, accept() itself carries the trade through to commit — don't overwrite that.
        if case .reviewingProposal = phase { phase = .waitingForPeerAccept }
    }

    private func rejectProposal() {
        session?.reject(reason: "user_declined")
        resetToIdle()
    }

    /// Releases the session — clears the callbacks before dropping the reference. If the old
    /// session overwrites this screen's phase while it's still alive during the fallback swap
    /// (while the transport layer is still flushing its last callback), the user ends up dragged
    /// into the wrong phase carrying the peer name of a connection already discarded.
    private func releaseSession() {
        guard let session else { return }
        session.onPeerIdentified = nil
        session.onOffersReady = nil
        session.onOfferWithdrawn = nil
        session.onReadyToCommit = nil
        session.onCompleted = nil
        session.onRejected = nil
        session.onDisconnected = nil
        session.disconnect()
        self.session = nil
    }

    /// `disconnect()` only tears down the MCSession — the advertiser/browser is only shut down by
    /// `stopDiscovery()`. Missing either one leaves the app still advertising the trade service,
    /// and an auto-accepted invite can wake a session that's already been discarded.
    private func releaseMultipeerTransport() {
        multipeerTransport?.stopDiscovery()
        multipeerTransport?.disconnect()
        multipeerTransport = nil
    }

    private func teardownConnection() {
        navigation.tradeSessionActive = false
        discoveryTimeout?.cancel()
        discoveryTimeout = nil
        releaseSession()
        releaseMultipeerTransport()
        manualTransport?.disconnect()
        manualTransport = nil
    }

    /// `.committing` means the local commit has already finished, so sending it through
    /// `resetToIdle` would clear, with a single click, the backup location and recovery guidance
    /// and the "peer's apply is uncertain" indicator that the spec requires — the file survives
    /// but loses its name. Instead, just disconnect and go to `.uncertain`, the same phase as the
    /// disconnect path (which is semantically accurate — this really is an uncertain state).
    private func closeFromCommitting() {
        teardownConnection()
        phase = .uncertain
    }

    private func resetToIdle() {
        teardownConnection()
        discoveredPeers = []
        connectedPeer = nil
        manualCodeInput = ""
        manualCodeInvalid = false
        lastBackupURL = nil
        connectFailed = false
        phase = .idle
    }
}
