import AppKit
import SwiftUI

/// The individual's nature as a badge, the size of the type and growth badges beside it (the owner, 2026-11-09: it
/// was written larger, so it stood out).
@MainActor
struct NatureBadge: View {
    let nature: PokemonNature
    let language: AppLanguage

    var body: some View {
        Badge(tint: .secondary, style: .tinted) {
            HStack(spacing: 2) {
                Image(systemName: "leaf.fill").font(.system(size: 6.5, weight: .bold))
                Text(nature.name(language))
            }
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

/// The Pokémon raised as a banner to paste in a conversation (the owner's friends, 2026-11-09: they took screenshots
/// of the card by hand). Drawn by the app from what it knows: no screen capture, nothing saved to a file.
@MainActor
struct CatchBanner: View {
    /// What the banner says, read once from the store.
    struct Info: Equatable {
        var name: String
        var number: Int
        var isShiny: Bool
        var rarity: Rarity?
        var types: [String]
        var nature: PokemonNature?
        /// Out of 186; nil without a profile.
        var ivTotal: Int?
        var dexLine: String
        var hatchedAt: Date?
    }

    static let width: CGFloat = 320
    /// The popover's background around the card, so the image is opaque everywhere (a pasted PNG's clear corners turn
    /// black in some conversations).
    static let margin: CGFloat = 10
    static let brand = "PokeTokenLBI"

    let store: CompanionStore
    let info: Info
    let sprite: NSImage?

    @MainActor
    static func info(_ store: CompanionStore) -> Info? {
        guard store.hasActive, let id = store.currentSpeciesID, let active = store.state.active else { return nil }
        let ivTotal = active.profile.map { p in CompanionStore.ivKeyPaths.reduce(0) { $0 + p.ivs[keyPath: $1] } }
        let progress = store.graduatedCollectionProgress
        return Info(name: store.displayName, number: id, isShiny: store.currentIsShiny, rarity: store.rarity,
                    types: PokemonTypeData.typeNames(speciesID: id, form: store.currentForm,
                                                     fallback: store.pokemonDetails(speciesID: id, form: store.currentForm)?.types),
                    nature: store.currentNature, ivTotal: ivTotal,
                    dexLine: store.l.dexSpeciesProgress(progress.species, of: progress.speciesTotal),
                    hatchedAt: active.raising?.hatchedAt)
    }

    var body: some View {
        let l = store.l
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                Group {
                    if let sprite {
                        Image(nsImage: sprite).interpolation(.none).resizable().scaledToFit()
                    } else {
                        Image(systemName: "questionmark").font(.system(size: 30, weight: .bold)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 80, height: 80)
                .background(alignment: .bottom) {
                    Ellipse().fill(Color.black.opacity(0.18)).frame(width: 52, height: 9).blur(radius: 2).offset(y: -2)
                }
                .frame(width: 84, height: 84)
                VStack(alignment: .leading, spacing: 4) {
                    WrappingHStack(spacing: 4, lineSpacing: 4) {
                        if let r = info.rarity {
                            if r == .legendary {
                                LegendaryBadge(text: l.rarityLabel(r).uppercased()).lineLimit(1).fixedSize()
                            } else {
                                Badge(l.rarityLabel(r).uppercased(), tint: .rarity(r)).lineLimit(1).fixedSize()
                            }
                        }
                        ActiveNewsBadges(store: store)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(info.name).font(.system(size: 17, weight: .bold, design: .rounded))
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        Text("#\(info.number)").font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary).monospacedDigit()
                        if info.isShiny { Text("✨").font(.system(size: 12)) }
                    }
                    WrappingHStack(spacing: 5, lineSpacing: 4) {
                        if !info.types.isEmpty { TypeBadges(types: info.types, language: store.language) }
                        if let nature = info.nature { NatureBadge(nature: nature, language: store.language) }
                        if let iv = info.ivTotal { Badge("IV \(iv)/186", tint: .blue, style: .tinted).fixedSize() }
                    }
                }
                Spacer(minLength: 0)
            }
            // What its graduation will advance, as Home shows it (the owner, 2026-11-16: missing from the image).
            ActiveGoalsList(store: store)
            HStack(spacing: 6) {
                Text(info.dexLine)
                Spacer(minLength: 4)
                Text(info.hatchedAt.map { "\(Self.brand) · \($0.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(store.language.displayLocale)))" }
                     ?? Self.brand)
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .frame(width: Self.width - 2 * Design.cardPadding, alignment: .leading)
        .heroCard(colors: store.themeColors, legendary: info.rarity == .legendary)
        .frame(width: Self.width)
        .padding(Self.margin)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// Draws the banner and puts it on the pasteboard.
@MainActor
enum CatchImage {
    /// Three pixels a point: sharp once a conversation scales it down.
    static let scale: CGFloat = 3

    /// The banner of the Pokémon raised, in `colorScheme`; nil for an egg. `sprite`: its still (the sprite cache, or
    /// PokéAPI the first time), on the main actor as `SpriteLoader` is: CI's macOS 15 SDK has no `Sendable` NSImage,
    /// so a nonisolated loader could not hand it back.
    static func render(_ store: CompanionStore, colorScheme: ColorScheme,
                       sprite load: @MainActor (_ speciesID: Int, _ shiny: Bool, _ form: PokemonForm?) async -> NSImage? = {
                           await SpriteLoader.image(speciesID: $0, shiny: $1, form: $2)
                       }) async -> CGImage? {
        guard let info = CatchBanner.info(store), let id = store.currentSpeciesID else { return nil }
        let sprite = await load(id, store.currentIsShiny, store.currentSpriteForm)
        let renderer = ImageRenderer(content: CatchBanner(store: store, info: info, sprite: sprite)
            .environment(\.colorScheme, colorScheme))
        renderer.scale = scale
        return renderer.cgImage
    }

    /// The image as PNG and TIFF, so a chat app and an image editor both take it. Nothing is written to a file.
    @discardableResult
    static func copy(_ image: CGImage, to pasteboard: NSPasteboard = .general) -> Bool {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let png = rep.representation(using: .png, properties: [:]), let tiff = rep.tiffRepresentation else {
            return false
        }
        pasteboard.clearContents()
        pasteboard.declareTypes([.png, .tiff], owner: nil)
        return pasteboard.setData(png, forType: .png) && pasteboard.setData(tiff, forType: .tiff)
    }
}

/// The card's discreet button, top right: copies the banner, then says so for a moment.
@MainActor
struct CatchCopyButton: View {
    let store: CompanionStore
    static let symbol = "camera.viewfinder"
    @Environment(\.colorScheme) private var colorScheme
    @State private var copied = false
    @State private var working = false

    var body: some View {
        let l = store.l
        Button {
            guard !working else { return }
            working = true
            Task {
                if let image = await CatchImage.render(store, colorScheme: colorScheme), CatchImage.copy(image) {
                    withAnimation(.easeOut(duration: 0.15)) { copied = true }
                    try? await Task.sleep(for: .seconds(1.6))
                    withAnimation(.easeIn(duration: 0.2)) { copied = false }
                }
                working = false
            }
        } label: {
            HStack(spacing: 4) {
                if copied {
                    Text(l.catchImageCopied).font(.system(size: 9, weight: .semibold))
                        .transition(.opacity)
                }
                Image(systemName: copied ? "checkmark" : Self.symbol)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(copied ? AnyShapeStyle(Design.actionColor) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 5).padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverTip(l.catchImageCopyHint)
        .accessibilityLabel(l.catchImageCopyHint)
    }
}
