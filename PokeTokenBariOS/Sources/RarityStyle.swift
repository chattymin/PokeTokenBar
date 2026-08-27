import SwiftUI

/// Rarity display helpers for phone-side payload strings
/// (rarity travels as its rawValue, e.g. "legendary").
enum RarityStyle {
    /// Precious first — same order as the Mac's rarity capsules.
    static let displayOrder = ["legendary", "rare", "uncommon", "common"]

    static func color(_ rarity: String) -> Color {
        switch rarity {
        case "uncommon": return .green
        case "rare": return .blue
        case "legendary": return .orange
        default: return .gray
        }
    }

    static func label(_ rarity: String) -> String {
        switch rarity {
        case "uncommon": return String(localized: "Uncommon")
        case "rare": return String(localized: "Rare")
        case "legendary": return String(localized: "Legendary")
        default: return String(localized: "Common")
        }
    }
}
