import SwiftUI

/// User-selectable app appearance preference.
enum AppAppearance: String, CaseIterable, Identifiable {
    /// Follow the system-wide appearance.
    case system
    /// Always render in light mode.
    case light
    /// Always render in dark mode.
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: String(localized: "System")
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        }
    }

    /// The color scheme to force, or `nil` to follow the system setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
