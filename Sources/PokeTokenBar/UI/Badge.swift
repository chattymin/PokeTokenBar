import SwiftUI

/// The 18 main-series types, keyed by PokeAPI's canonical lowercase English name.
enum PokemonType: String, Codable, Sendable, CaseIterable {
    case normal, fire, water, electric, grass, ice, fighting, poison, ground,
         flying, psychic, bug, rock, ghost, dragon, dark, steel, fairy

    init?(apiName: String) { self.init(rawValue: apiName.lowercased()) }

    /// Classic type-chart colors.
    var hex: UInt32 {
        switch self {
        case .normal: 0xAAAA99
        case .fire: 0xFF4422
        case .water: 0x3399FF
        case .electric: 0xFFCC33
        case .grass: 0x77CC55
        case .ice: 0x66CCFF
        case .fighting: 0xBB5544
        case .poison: 0xAA5599
        case .ground: 0xDDBB55
        case .flying: 0x8899FF
        case .psychic: 0xFF5599
        case .bug: 0xAABB22
        case .rock: 0xBBAA66
        case .ghost: 0x6666BB
        case .dragon: 0x7766EE
        case .dark: 0x775544
        case .steel: 0xAAAABB
        case .fairy: 0xEE99EE
        }
    }

    var color: Color {
        Color(.sRGB, red: Double((hex >> 16) & 0xFF) / 255,
              green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255)
    }
}

/// What a `Badge` is colored by.
enum BadgeTint {
    /// nil = a PokeAPI type outside the 18 (stellar, shadow, unknown) → neutral gray.
    case type(PokemonType?)
    case rarity(Rarity?)
    case accent, orange, secondary

    var color: Color {
        switch self {
        case .type(let type): type?.color ?? .gray
        case .rarity(let rarity): rarityColor(rarity)
        case .accent: .accentColor
        case .orange: .orange
        case .secondary: .secondary
        }
    }
}

/// Small capsule label shared by rarity, type and status pills.
/// `.solid` = white text on the tint (rarity, type); `.tinted` = tint text on a faint tint (RAISING, boosts).
@MainActor
struct Badge<Label: View>: View {
    enum Style { case solid, tinted }

    let tint: BadgeTint
    var style: Style = .solid
    var size: CGFloat = 8
    var horizontalPadding: CGFloat = 5
    var verticalPadding: CGFloat = 1
    @ViewBuilder var label: Label

    var body: some View {
        label
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(style == .solid ? Color.white : tint.color)
            // Light type fills (electric, ice, fairy…) keep white text legible the way the game chart does.
            .shadow(color: isType ? .black.opacity(0.35) : .clear, radius: 0.5, y: 0.5)
            .padding(.horizontal, horizontalPadding).padding(.vertical, verticalPadding)
            .background(style == .solid ? tint.color : tint.color.opacity(0.14), in: Capsule())
    }

    private var isType: Bool { if case .type = tint { true } else { false } }
}

extension Badge where Label == Text {
    init(_ text: String, tint: BadgeTint, style: Style = .solid, size: CGFloat = 8) {
        self.init(tint: tint, style: style, size: size) { Text(text) }
    }
}

/// A species' type row — one `Badge` per type, with the localized type name.
@MainActor
struct TypeBadges: View {
    let types: [String]
    let language: AppLanguage
    var size: CGFloat = 8
    var horizontalPadding: CGFloat = 5
    var verticalPadding: CGFloat = 1

    var body: some View {
        HStack(spacing: 5) {
            ForEach(types, id: \.self) { type in
                Badge(tint: .type(PokemonType(apiName: type)), size: size,
                      horizontalPadding: horizontalPadding, verticalPadding: verticalPadding) {
                    PokemonNameLabel(.type, type, language: language).textCase(.uppercase)
                }
            }
        }
    }
}
