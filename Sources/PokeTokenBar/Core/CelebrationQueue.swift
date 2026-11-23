import Foundation

/// Who is celebrating: a species (or the egg, `speciesID == nil`) with its individual appearance.
struct CelebrationSubject: Equatable, Sendable {
    let speciesID: Int?
    let form: PokemonForm?
    let isShiny: Bool
    /// Localized when the item is queued. A language switch mid-sequence keeps this name, so one sequence
    /// can mix two languages (accepted: it lasts one sequence and needs no extra state).
    let name: String
}

enum CelebrationKind: Equatable, Sendable {
    case hatch(to: CelebrationSubject)
    case evolve(from: CelebrationSubject, to: CelebrationSubject)
    case dittoReveal(shiny: Bool)
}

/// A surface that can play a celebration.
enum CelebrationSurface: Hashable, Sendable { case popover, floatingPet }

/// The notification held back until the sequence that announces it has finished.
struct DeferredCompanionEvent: Equatable, Sendable {
    let title: String
    let body: String
    let levelUpSeconds: TimeInterval
    /// A graduation's name: once released it also shows the "graduated" line instead of the level-up window.
    var graduated: String? = nil
}

struct PendingCelebration: Equatable, Identifiable, Sendable {
    let id: Int
    let kind: CelebrationKind
    var deferred: DeferredCompanionEvent?
    /// The companion's generation when the item was queued: a new companion drops the older ones.
    var generation = 0

    /// The Ditto reveal has no floating-pet sequence.
    func isPlayable(on surface: CelebrationSurface) -> Bool {
        if case .dittoReveal = kind { return surface == .popover }
        return true
    }
}

struct CelebrationQueue: Equatable, Sendable {
    private(set) var items: [PendingCelebration] = []
    /// Notices without a sequence (graduation, Ditto reveal) that arrived while a queued item still held its
    /// notification. Each waits behind that item, so no notification ever overtakes an earlier one.
    private(set) var heldNotices: [HeldNotice] = []
    private var nextID = 1

    struct HeldNotice: Equatable, Sendable {
        /// The last item holding a notification when the notice arrived.
        let afterID: Int
        let event: DeferredCompanionEvent
    }

    /// The id of the most recently queued item; only grows, so a new item behind an unseen head changes it.
    var lastEnqueuedID: Int { nextID - 1 }

    /// The surfaces that play sequences right now. With the popover open and the pet on screen both play the
    /// head at the same time; the first to reach its end marks it seen, so closing the popover never replays it.
    static func liveSurfaces(popoverOpen: Bool, floatingPetLive: Bool) -> Set<CelebrationSurface> {
        var surfaces: Set<CelebrationSurface> = []
        if popoverOpen { surfaces.insert(.popover) }
        if floatingPetLive { surfaces.insert(.floatingPet) }
        return surfaces
    }

    /// The popover is live only while someone can see it: shown, display awake, session interactive.
    /// Behind a sleeping display or a lock screen it counts as closed, so nothing plays (or is seen) there.
    static func popoverLive(shown: Bool, displayAwake: Bool, sessionInteractive: Bool) -> Bool {
        shown && displayAwake && sessionInteractive
    }

    @discardableResult
    mutating func enqueue(_ kind: CelebrationKind, deferred: DeferredCompanionEvent?, generation: Int = 0) -> Int {
        let id = nextID
        nextID += 1
        items.append(PendingCelebration(id: id, kind: kind, deferred: deferred, generation: generation))
        return id
    }

    func next(for surface: CelebrationSurface) -> PendingCelebration? {
        items.first { $0.isPlayable(on: surface) }
    }

    /// Holds `event` behind the last item still holding a notification. false: nothing is held, send it now.
    mutating func hold(_ event: DeferredCompanionEvent) -> Bool {
        guard let last = items.last(where: { $0.deferred != nil }) else { return false }
        heldNotices.append(HeldNotice(afterID: last.id, event: event))
        return true
    }

    /// Removes the item with `id`. Returns its notification, then the notices nothing holds back any more.
    @discardableResult
    mutating func remove(id: Int) -> [DeferredCompanionEvent] {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return [] }
        return released(removing: [items.remove(at: index)])
    }

    /// Removes the item with `id` and everything queued after it (ids only grow); their notifications in order.
    @discardableResult
    mutating func removeFrom(id: Int) -> [DeferredCompanionEvent] {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return [] }
        let removed = Array(items[index...])
        items.removeSubrange(index...)
        return released(removing: removed)
    }

    /// Removes the items queued for an earlier companion, except `keeping` (the one on screen); their
    /// notifications in order.
    @discardableResult
    mutating func removeGenerations(before generation: Int, keeping kept: Int? = nil) -> [DeferredCompanionEvent] {
        func dropped(_ item: PendingCelebration) -> Bool { item.generation < generation && item.id != kept }
        let removed = items.filter(dropped)
        items.removeAll(where: dropped)
        return released(removing: removed)
    }

    /// Clears every held notification and notice (the items stay queued) and returns them in order.
    mutating func takeDeferredEvents() -> [DeferredCompanionEvent] {
        let events = Self.ordered(deferredOf: items, notices: heldNotices)
        for index in items.indices { items[index].deferred = nil }
        heldNotices = []
        return events
    }

    /// The removed items' notifications plus the notices no remaining item holds back, in arrival order.
    private mutating func released(removing removed: [PendingCelebration]) -> [DeferredCompanionEvent] {
        // A notice waits while an item at or before its place still holds a notification.
        let firstHeld = items.first { $0.deferred != nil }?.id ?? Int.max
        let free = heldNotices.prefix { $0.afterID < firstHeld }
        heldNotices.removeFirst(free.count)
        return Self.ordered(deferredOf: removed, notices: Array(free))
    }

    /// An item's notification came before any notice held behind it; ids and notices only grow.
    private static func ordered(deferredOf items: [PendingCelebration], notices: [HeldNotice]) -> [DeferredCompanionEvent] {
        let fromItems = items.compactMap { item in item.deferred.map { (key: item.id, rank: 0, event: $0) } }
        let fromNotices = notices.map { (key: $0.afterID, rank: 1, event: $0.event) }
        // Stable: notices behind the same item keep their arrival order.
        return (fromItems + fromNotices).enumerated()
            .sorted { ($0.element.key, $0.element.rank, $0.offset) < ($1.element.key, $1.element.rank, $1.offset) }
            .map(\.element.event)
    }
}
