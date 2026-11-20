import SwiftUI

// The popover header's celebration stage, lifted out of the Home ScrollView: the header publishes its
// sprite slot while a sequence plays, and `celebrationStageHost()` draws the stage on it from above.

/// The header's sprite slot while a sequence plays, with what the stage needs to draw it.
struct CelebrationStageAnchor {
    let slot: Anchor<CGRect>
    let player: CelebrationPlayer
    let spriteStore: SpriteStore
}

struct CelebrationStageAnchorKey: PreferenceKey {
    static var defaultValue: CelebrationStageAnchor? { nil }
    static func reduce(value: inout CelebrationStageAnchor?, nextValue: () -> CelebrationStageAnchor?) {
        if value == nil { value = nextValue() }
    }
}

extension View {
    /// Draws the playing celebration stage over this view, grounded on the sprite slot the header
    /// publishes: the slot grown by `effectsMargin` on every side, so the sprite at scale 1 sits exactly on
    /// the resting sprite. Applied above the popover's ScrollView, the effects are clipped only by the
    /// popover itself and may cover the tab picker; no other element moves.
    func celebrationStageHost() -> some View {
        overlayPreferenceValue(CelebrationStageAnchorKey.self) { anchor in
            if let anchor {
                GeometryReader { proxy in
                    let slot = proxy[anchor.slot]
                    let margin = CelebrationStage.effectsMargin
                    CelebrationStage(player: anchor.player, size: slot.width, spriteStore: anchor.spriteStore)
                        .frame(width: slot.width + 2 * margin, height: slot.height + 2 * margin)
                        .position(x: slot.midX, y: slot.midY)
                }
            }
        }
    }
}

/// A vertical `ScrollView` whose content starts with `CompanionHeader`. When a popover celebration
/// arrives it scrolls back to the top first, so the sequence never plays (and counts as seen) while
/// the header's sprite is scrolled out of the viewport, and it does not scroll while one is pending:
/// the stage is drawn above it and would drift over other controls. Reserves the popover's scroller lane.
@MainActor
struct CelebrationScrollView<Content: View>: View {
    let companion: CompanionStore
    @ViewBuilder let content: Content
    private static var topID: String { "celebrationScrollTop" }

    /// The popover is live and has an item to play on the header.
    static func scrollLocked(companion: CompanionStore) -> Bool {
        companion.isLive(.popover) && companion.celebrations.next(for: .popover) != nil
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content
                    .reservesScrollerLane()
                    .id(Self.topID)
            }
            .scrollDisabled(Self.scrollLocked(companion: companion))
            // Every new item, even one queued behind an unseen head (the head id would not change).
            .onChange(of: companion.celebrations.lastEnqueuedID) {
                if companion.celebrations.next(for: .popover) != nil { proxy.scrollTo(Self.topID, anchor: .top) }
            }
        }
    }
}
