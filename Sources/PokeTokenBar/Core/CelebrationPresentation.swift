import Foundation

/// Who a surface shows for the companion while hatch / evolve sequences are pending. The store switches
/// species before any sequence plays, so with a chain queued (hatch then a carry-over evolve, two rare
/// candies) its live state is already the end of the chain. One rule for every surface (the popover header's
/// name, line, sprite and VoiceOver name; the floating pet's sprite): no result before its own reveal.
enum CelebrationPresentation: Equatable {
    /// The egg: a pending hatch's source.
    case egg
    /// A species with its stage completed: an evolve's source, or a revealed result while a later item waits.
    case subject(CelebrationSubject)

    /// The name shown (and read by VoiceOver).
    var name: String {
        switch self {
        case .egg: CompanionStore.eggName
        case .subject(let subject): subject.name
        }
    }

    /// The species shown; nil for the egg.
    var speciesID: Int? {
        switch self {
        case .egg: nil
        case .subject(let subject): subject.speciesID
        }
    }

    /// The reveal caption is the moment a sequence's result may be shown; before it, nothing names it.
    static func isRevealed(_ text: CelebrationText) -> Bool {
        text == .evolveDone || text == .hatchDone
    }

    /// What `surface` shows; nil = the store's live state.
    ///
    /// - Before its reveal caption, the playing item's source (the egg for a hatch).
    /// - After it, the result, as long as a later item playable on `surface` still waits, or the live companion
    ///   (`liveSpeciesID`, nil for an egg) is no longer that result: the live state is already past that item
    ///   (Reduce Motion reveals at t = 0, so this holds from the first frame; a chain's last evolution can end
    ///   in a graduation, whose new egg must not show during the reveal caption).
    /// - Nothing playing (before the first item, between two items, or this surface is not live): the
    ///   source of the next item, so the resting sprite never flashes the end of the chain.
    static func shown(queue: CelebrationQueue, playing: PendingCelebration?, text: CelebrationText,
                      surface: CelebrationSurface, liveSpeciesID: Int?) -> CelebrationPresentation? {
        if let playing, let stages = stages(of: playing.kind) {
            guard isRevealed(text) else { return stages.source }
            let laterItemWaits = queue.items.contains { $0.id > playing.id && $0.isPlayable(on: surface) }
            let liveIsPastIt = stages.target.speciesID != liveSpeciesID
            return laterItemWaits || liveIsPastIt ? stages.target : nil
        }
        return queue.next(for: surface).flatMap { stages(of: $0.kind)?.source }
    }

    /// Where a sequence starts and what it reveals. nil for a Ditto reveal: it has no stage sequence, and
    /// its flash happens on the live state.
    private static func stages(of kind: CelebrationKind)
        -> (source: CelebrationPresentation, target: CelebrationPresentation)? {
        switch kind {
        case .hatch(let to): (.egg, .subject(to))
        case .evolve(let from, let to): (.subject(from), .subject(to))
        case .dittoReveal: nil
        }
    }
}
