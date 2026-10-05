import AppKit

/// The menu bar item's secondary-click menu. Left click still toggles the popover; right click or
/// Control-click opens this menu for the actions people reach for without reading the popover.
///
/// The contents are plain values so tests can pin them without an `NSStatusItem`.
@MainActor
enum StatusItemMenu {
    enum Action: Equatable {
        case refresh, openDex, openSettings, toggleFloatingPet, quit
    }

    struct Entry: Equatable {
        let title: String
        let keyEquivalent: String
        /// `nil` is an informational row: shown greyed out, not clickable.
        let action: Action?
    }

    /// `nil` elements are separators.
    static func entries(l: L, todayTokens: Int, todayCost: UsageCost?, floatingPetEnabled: Bool) -> [Entry?] {
        [
            Entry(title: summary(l: l, todayTokens: todayTokens, todayCost: todayCost), keyEquivalent: "", action: nil),
            nil,
            Entry(title: l.refreshNow, keyEquivalent: "r", action: .refresh),
            Entry(title: l.dexTitle, keyEquivalent: "d", action: .openDex),
            Entry(title: l.settings + "…", keyEquivalent: ",", action: .openSettings),
            Entry(title: floatingPetEnabled ? l.floatingPetHideLabel : l.floatingPetEnableLabel,
                  keyEquivalent: "", action: .toggleFloatingPet),
            nil,
            Entry(title: l.quit, keyEquivalent: "q", action: .quit),
        ]
    }

    /// "Today's tokens 19.4M · $5.09". The cost is left out when no provider reports one,
    /// matching the popover header.
    static func summary(l: L, todayTokens: Int, todayCost: UsageCost?) -> String {
        let tokens = "\(l.todayTokens) \(TokenFormatter.compact(todayTokens))"
        guard let todayCost else { return tokens }
        return "\(tokens) · \(todayCost.text(l))"
    }

    /// Right click, or Control + left click (the standard one-button secondary click).
    static func opensMenu(eventType: NSEvent.EventType?, modifiers: NSEvent.ModifierFlags) -> Bool {
        switch eventType {
        case .rightMouseDown, .rightMouseUp: return true
        case .leftMouseDown, .leftMouseUp: return modifiers.contains(.control)
        default: return false
        }
    }

    /// Each item carries its `Action` in `representedObject`; `selector` receives the `NSMenuItem`.
    static func build(_ entries: [Entry?], target: AnyObject, selector: Selector) -> NSMenu {
        let menu = NSMenu(title: "")
        menu.autoenablesItems = false
        for entry in entries {
            guard let entry else {
                menu.addItem(.separator())
                continue
            }
            let item = NSMenuItem(title: entry.title, action: entry.action == nil ? nil : selector,
                                  keyEquivalent: entry.keyEquivalent)
            item.target = entry.action == nil ? nil : target
            item.representedObject = entry.action.map(ActionBox.init)
            item.isEnabled = entry.action != nil
            menu.addItem(item)
        }
        return menu
    }

    static func action(of item: NSMenuItem) -> Action? {
        (item.representedObject as? ActionBox)?.action
    }

    /// `representedObject` takes `Any`, but boxing keeps the cast in one place.
    private final class ActionBox: NSObject {
        let action: Action
        init(_ action: Action) { self.action = action }
    }
}
