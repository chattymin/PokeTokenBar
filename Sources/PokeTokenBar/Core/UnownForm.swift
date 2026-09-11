import Foundation

/// Unown's letter is an individual attribute, independent of its species and shiny color.
enum UnownForm: String, CaseIterable, Codable, Hashable, Sendable {
    case a, b, c, d, e, f, g, h, i, j, k, l, m
    case n, o, p, q, r, s, t, u, v, w, x, y, z
    case exclamation, question

    static let speciesID = 201

    var symbol: String {
        switch self {
        case .exclamation: return "!"
        case .question: return "?"
        default: return rawValue.uppercased()
        }
    }

    var sortOrder: Int { Self.allCases.firstIndex(of: self)! }

    static func roll(_ roll: UInt64) -> UnownForm {
        allCases[Int(roll % UInt64(allCases.count))]
    }

    /// Older saves displayed the default A sprite. Preserve that appearance when no form exists.
    static func resolved(speciesID: Int, form: UnownForm?) -> UnownForm? {
        speciesID == Self.speciesID ? (form ?? .a) : nil
    }

    static func displayName(_ name: String, speciesID: Int, form: UnownForm?) -> String {
        guard let form = resolved(speciesID: speciesID, form: form) else { return name }
        return "\(name) [\(form.symbol)]"
    }
}
