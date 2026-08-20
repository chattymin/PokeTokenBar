import Foundation

/// Minimal language enum shared between iOS app and widget.
public enum AppLanguage: String, Codable, Sendable, CaseIterable {
    case ko, en, ja, es

    public var label: String {
        switch self {
        case .ko: return "한국어"
        case .en: return "English"
        case .ja: return "日本語"
        case .es: return "Español"
        }
    }

    public var displayLocale: Locale { Locale(identifier: rawValue) }

    public static var systemDefault: AppLanguage {
        switch Locale.preferredLanguages.first?.prefix(2).lowercased() {
        case "ko": return .ko
        case "ja": return .ja
        case "es": return .es
        default:   return .en
        }
    }
}
