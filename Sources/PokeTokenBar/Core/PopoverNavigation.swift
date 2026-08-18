import Foundation
import Observation

/// The popover's tabs. Shared by both frontends — the macOS popover and the Linux window show the
/// same four, and a tab that exists on one platform only is a parity bug waiting to happen.
enum PopoverTab: String, CaseIterable {
    case home, shop, bag, collection

    /// Parse a tab from a command-line name; nil for anything unrecognised.
    init?(name: String) {
        guard let match = PopoverTab(rawValue: name.lowercased()) else { return nil }
        self = match
    }
}

/// Navigation state inside the popover (current tab / whether settings is showing).
///
/// On macOS `NSHostingController` survives the popover closing, so `@State` would persist; the
/// screen state is split into this Observable and `AppDelegate` calls `reset()` on each open, which
/// is what makes reopening always land on Home.
@MainActor
@Observable
final class PopoverNavigation {
    var showSettings = false
    var tab: PopoverTab = .home
    /// Selected provider tab — deliberately *not* reset, so reopening keeps the service you were on.
    var providerID: String?

    func reset() {
        showSettings = false
        tab = .home
    }
}
