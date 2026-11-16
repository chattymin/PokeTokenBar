import AppKit
import SwiftUI

/// Whether a view is drawn for a card's image (`CardSnapshotButton`): the button itself stays out of the picture.
private struct CardSnapshotKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isCardSnapshot: Bool {
        get { self[CardSnapshotKey.self] }
        set { self[CardSnapshotKey.self] = newValue }
    }
}

/// A Home card's discreet button, top right: copies the card as it stands, then says so for a moment (the owner,
/// 2026-11-16: the expedition under way and its result, as the Pokémon raised's card is copied). The card is drawn
/// again by the app, its sprites from the cache it shows them from: no screen capture, nothing written to a file.
@MainActor
struct CardSnapshotButton<Card: View>: View {
    let store: CompanionStore
    /// The sprites the card shows, loaded first so the drawing finds them in the cache (`SpriteView` reads it at once).
    var sprites: [(speciesID: Int, shiny: Bool, form: PokemonForm?)] = []
    let card: () -> Card
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isCardSnapshot) private var isSnapshot
    @State private var copied = false

    var body: some View {
        if !isSnapshot {
            let l = store.l
            Button {
                let sprites = sprites
                Task {
                    for sprite in sprites { _ = await SpriteLoader.image(speciesID: sprite.speciesID, shiny: sprite.shiny, form: sprite.form) }
                    guard let image = Self.render(card(), colorScheme: colorScheme), CatchImage.copy(image) else { return }
                    withAnimation(.easeOut(duration: 0.15)) { copied = true }
                    try? await Task.sleep(for: .seconds(1.6))
                    withAnimation(.easeIn(duration: 0.2)) { copied = false }
                }
            } label: {
                HStack(spacing: 4) {
                    if copied {
                        Text(l.catchImageCopied).font(.system(size: 9, weight: .semibold)).transition(.opacity)
                    }
                    Image(systemName: copied ? "checkmark" : CatchCopyButton.symbol).font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(copied ? AnyShapeStyle(Design.actionColor) : AnyShapeStyle(.secondary))
                .padding(.horizontal, 5).padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverTip(l.cardImageCopyHint)
            .accessibilityLabel(l.cardImageCopyHint)
        }
    }

    /// The card at the popover's width on its background, three pixels a point, in `colorScheme`.
    static func render(_ card: Card, colorScheme: ColorScheme) -> CGImage? {
        let renderer = ImageRenderer(content: card
            .environment(\.isCardSnapshot, true)
            .frame(width: PopoverMetrics.scrollContentWidth)
            .padding(CatchBanner.margin)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, colorScheme))
        renderer.scale = CatchImage.scale
        return renderer.cgImage
    }
}
