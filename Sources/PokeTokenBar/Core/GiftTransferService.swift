import Foundation
import Network
import Observation

/// Keeps the final connection cleanup behind the transport's completion callback. This tiny seam
/// is intentionally testable without Network.framework so a future refactor cannot reintroduce
/// `send(); cancel()` ordering.
@MainActor
enum GiftTransferFinalization {
    static func afterSendStarts(
        _ start: (@escaping @MainActor () -> Void) -> Void,
        cleanup: @escaping @MainActor () -> Void
    ) {
        start(cleanup)
    }
}

/// Bonjour discovery + a tiny idempotent TCP protocol for nearby gifts.
/// No user name, item, or pairing code is published in Bonjour metadata.
@MainActor
@Observable
final class GiftTransferService {
    enum Status: Equatable {
        case idle
        case offering
        case searching
        case sent(ItemKind)
        case received(ItemKind)
        case failed
    }

    private struct WireMessage: Codable, Sendable {
        enum Kind: String, Codable, Sendable { case claim, offer, receipt, committed, rejected }
        let kind: Kind
        var code: String?
        var gift: PendingGift?
        var giftID: UUID?
    }

    nonisolated static let serviceType = "_poketokenbar._tcp"
    nonisolated static let maxMessageBytes = 8 * 1024
    nonisolated static let pairingAlphabet = Array("23456789ABCDEFGHJKLMNPQRSTUVWXYZ")

    private let store: CompanionStore
    private let queue = DispatchQueue(label: "io.github.chattymin.poketokenbar.gift")
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var connections: [NWConnection] = []
    private var expiryTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private(set) var status: Status = .idle

    init(store: CompanionStore) {
        self.store = store
        store.discardExpiredGift()
        // A listener cannot survive process termination. Release a still-valid reservation on
        // relaunch instead of showing a code that no peer can reach.
        if let orphaned = store.pendingGift { store.cancelGift(id: orphaned.id) }
    }

    var activeOffer: PendingGift? { store.pendingGift }

    static func makePairingCode() -> String {
        String((0..<6).map { _ in pairingAlphabet.randomElement()! })
    }

    @discardableResult
    func startOffering(_ kind: ItemKind) -> Bool {
        stopNetworking()
        let gift: PendingGift
        if let pending = store.pendingGift, pending.kind == kind {
            gift = pending
        } else {
            if let pending = store.pendingGift { store.cancelGift(id: pending.id) }
            guard let created = store.beginGift(kind, code: Self.makePairingCode()) else {
                status = .failed
                return false
            }
            gift = created
        }

        do {
            let listener = try NWListener(using: .tcp)
            listener.service = NWListener.Service(name: "PokeTokenBar-\(gift.id.uuidString.prefix(8))",
                                                  type: Self.serviceType)
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection, gift: gift) }
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    switch state {
                    case .ready: self.status = .offering
                    case .failed:
                        self.store.cancelGift(id: gift.id)
                        self.stopNetworking()
                        self.status = .failed
                    default: break
                    }
                }
            }
            self.listener = listener
            listener.start(queue: queue)
            status = .offering
            scheduleExpiry(for: gift)
            return true
        } catch {
            store.cancelGift(id: gift.id)
            status = .failed
            return false
        }
    }

    func cancelOffer() {
        if let gift = store.pendingGift { store.cancelGift(id: gift.id) }
        stopNetworking()
        status = .idle
    }

    func receive(code rawCode: String) {
        let code = Self.normalized(code: rawCode)
        guard code.count == 6 else { status = .failed; return }
        stopNetworking()
        status = .searching

        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                guard let self, self.status == .searching else { return }
                for result in results where !self.connections.contains(where: { $0.endpoint == result.endpoint }) {
                    self.tryReceiverConnection(to: result.endpoint, code: code)
                }
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed = state { Task { @MainActor in self?.finishSearch(success: false) } }
        }
        self.browser = browser
        browser.start(queue: queue)
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.finishSearch(success: false) }
        }
    }

    func clearStatus() {
        guard store.pendingGift == nil else { return }
        status = .idle
    }

    private func accept(_ connection: NWConnection, gift: PendingGift) {
        guard connections.count < 8 else { connection.cancel(); return }
        connections.append(connection)
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let connection else { return }
            switch state {
            case .ready:
                Task { @MainActor in
                    self?.receiveMessage(on: connection) { message in
                        Task { @MainActor in self?.handleClaim(message, on: connection, gift: gift) }
                    }
                }
            case .failed, .cancelled:
                Task { @MainActor in self?.connections.removeAll { $0 === connection } }
            default: break
            }
        }
        connection.start(queue: queue)
    }

    private func handleClaim(_ message: WireMessage?, on connection: NWConnection, gift: PendingGift) {
        guard message?.kind == .claim,
              Self.normalized(code: message?.code ?? "") == gift.code,
              store.pendingGift?.id == gift.id else {
            send(WireMessage(kind: .rejected), on: connection, thenCancel: true)
            return
        }
        send(WireMessage(kind: .offer, gift: gift), on: connection)
        receiveMessage(on: connection) { [weak self] receipt in
            Task { @MainActor in
                guard let self, receipt?.kind == .receipt, receipt?.giftID == gift.id,
                      self.store.completeGift(id: gift.id) else {
                    self?.send(WireMessage(kind: .rejected), on: connection, thenCancel: true)
                    return
                }
                self.status = .sent(gift.kind)
                GiftTransferFinalization.afterSendStarts({ completion in
                    self.send(WireMessage(kind: .committed, giftID: gift.id), on: connection,
                              thenCancel: true, completion: completion)
                }, cleanup: { [weak self] in
                    self?.stopNetworking(keepingStatus: true)
                })
            }
        }
    }

    private func tryReceiverConnection(to endpoint: NWEndpoint, code: String) {
        let connection = NWConnection(to: endpoint, using: .tcp)
        connections.append(connection)
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let connection else { return }
            switch state {
            case .ready:
                Task { @MainActor in
                    self?.send(WireMessage(kind: .claim, code: code), on: connection)
                    self?.receiveMessage(on: connection) { message in
                        Task { @MainActor in self?.handleOffer(message, on: connection) }
                    }
                }
            case .failed, .cancelled:
                Task { @MainActor in self?.connections.removeAll { $0 === connection } }
            default: break
            }
        }
        connection.start(queue: queue)
    }

    private func handleOffer(_ message: WireMessage?, on connection: NWConnection) {
        guard status == .searching, message?.kind == .offer, let gift = message?.gift else {
            connection.cancel()
            return
        }
        let result = store.receiveGift(gift)
        guard result == .received || result == .alreadyReceived else {
            connection.cancel()
            finishSearch(success: false)
            return
        }
        browser?.cancel()
        browser = nil
        for other in connections where other !== connection { other.cancel() }
        connections = [connection]
        // The item is already durably in the bag at this point. A lost final confirmation must not
        // turn that successful local outcome into an error banner.
        status = .received(gift.kind)
        send(WireMessage(kind: .receipt, giftID: gift.id), on: connection)
        receiveMessage(on: connection) { [weak self] reply in
            Task { @MainActor in
                guard reply?.kind == .committed, reply?.giftID == gift.id else {
                    self?.stopNetworking(keepingStatus: true)
                    return
                }
                self?.stopNetworking(keepingStatus: true)
            }
        }
    }

    private func receiveMessage(on connection: NWConnection,
                                completion: @escaping @Sendable (WireMessage?) -> Void) {
        receiveMessage(on: connection, buffer: Data(), completion: completion)
    }

    private func receiveMessage(on connection: NWConnection, buffer: Data,
                                completion: @escaping @Sendable (WireMessage?) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: Self.maxMessageBytes) {
            [weak self] data, _, isComplete, error in
            guard let self, error == nil else { completion(nil); return }
            var next = buffer
            if let data { next.append(data) }
            guard next.count <= Self.maxMessageBytes else { completion(nil); return }
            if let newline = next.firstIndex(of: 0x0A) {
                completion(try? JSONDecoder().decode(WireMessage.self, from: next[..<newline]))
            } else if isComplete {
                completion(nil)
            } else {
                Task { @MainActor in
                    self.receiveMessage(on: connection, buffer: next, completion: completion)
                }
            }
        }
    }

    private func send(_ message: WireMessage, on connection: NWConnection, thenCancel: Bool = false,
                      completion: (@MainActor () -> Void)? = nil) {
        guard var data = try? JSONEncoder().encode(message) else {
            connection.cancel()
            completion?()
            return
        }
        data.append(0x0A)
        connection.send(content: data, completion: .contentProcessed { _ in
            Task { @MainActor in
                if thenCancel { connection.cancel() }
                completion?()
            }
        })
    }

    private func scheduleExpiry(for gift: PendingGift) {
        expiryTask?.cancel()
        expiryTask = Task { [weak self] in
            let delay = max(0, gift.expiresAt.timeIntervalSinceNow)
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.store.pendingGift?.id == gift.id else { return }
                self.store.cancelGift(id: gift.id)
                self.stopNetworking()
                self.status = .idle
            }
        }
    }

    private func finishSearch(success: Bool) {
        guard status == .searching else { return }
        stopNetworking()
        if !success { status = .failed }
    }

    private func stopNetworking(keepingStatus: Bool = false) {
        listener?.cancel(); listener = nil
        browser?.cancel(); browser = nil
        for connection in connections { connection.cancel() }
        connections.removeAll()
        expiryTask?.cancel(); expiryTask = nil
        searchTask?.cancel(); searchTask = nil
        if !keepingStatus { status = .idle }
    }

    private static func normalized(code: String) -> String {
        code.uppercased().filter { pairingAlphabet.contains($0) }
    }
}
