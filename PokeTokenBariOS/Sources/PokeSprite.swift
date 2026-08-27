import SwiftUI
import PokeTokenBarShared

/// Sprite image backed by `SpriteCache` — renders from cache immediately (no spinner on
/// revisits) and only downloads on a miss. `key` is the cache file name.
struct CachedSprite<Placeholder: View>: View {
    let url: URL?
    let key: String
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: UIImage?

    init(url: URL?, key: String, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.key = key
        self.placeholder = placeholder
        _image = State(initialValue: SpriteCache.shared.cachedImage(key: key))
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().interpolation(.none)
            } else {
                placeholder()
            }
        }
        // Always resolve the current key: SwiftUI keeps this view's @State across a key change
        // (e.g. the companion evolving), so an `if image == nil` guard would keep the old sprite.
        .task(id: key) {
            image = await SpriteCache.shared.image(for: url, key: key)
        }
    }
}

/// Species sprite (pixelated) — companion card, dex cells, empty states.
struct SpeciesSprite: View {
    let speciesID: Int
    let shiny: Bool
    let size: CGFloat

    var body: some View {
        CachedSprite(url: PokeSpriteURL.species(id: speciesID, shiny: shiny),
                     key: PokeSpriteURL.speciesKey(id: speciesID, shiny: shiny)) {
            ProgressView()
        }
        .frame(width: size, height: size)
    }
}

/// Item icon — PokéAPI item sprite with emoji fallback. Shared by bag/shop cards.
struct ItemIconView: View {
    let iconName: String?
    let fallbackEmoji: String
    let size: CGFloat

    var body: some View {
        Group {
            if let iconName {
                CachedSprite(url: PokeSpriteURL.item(name: iconName),
                             key: PokeSpriteURL.itemKey(name: iconName)) {
                    Text(fallbackEmoji).font(.system(size: size * 0.6))
                }
            } else {
                Text(fallbackEmoji).font(.system(size: size * 0.6))
            }
        }
        .frame(width: size, height: size)
    }
}
