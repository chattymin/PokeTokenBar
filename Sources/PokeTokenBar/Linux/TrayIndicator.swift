#if os(Linux)
import CGtk
import Foundation

/// The tray item — an AppIndicator (StatusNotifierItem) attached to the KDE/GNOME panel.
///
/// It stands in for macOS's `NSStatusItem` but is not as expressive:
/// - Icons are set by **name within a theme directory**, not as images. So sprites are written to
///   disk and swapped by name (`setIcon`).
/// - The label (`app_indicator_set_label`) may not render at all, depending on the panel widget.
///   Putting the numbers only in the label would leave the app mute on those panels, so **the same
///   value is always written to the first menu row too.**
@MainActor
final class TrayIndicator {
    private let indicator: UnsafeMutablePointer<AppIndicator>
    private let menu: UnsafeMutablePointer<GtkWidget>
    /// A disabled menu row showing the usage summary — the fallback for panels that hide labels.
    private let summaryItem: UnsafeMutablePointer<GtkWidget>

    /// - Parameters:
    ///   - iconThemePath: the directory sprite PNGs are written to.
    ///   - iconName: a filename inside that directory, without the extension.
    init(id: String, iconThemePath: String, iconName: String, summaryPlaceholder: String) {
        // GTK/AppIndicator constructors only return nil on allocation failure. Stopping here
        // beats threading optionals through every later call — without a tray there is no app.
        indicator = app_indicator_new_with_path(
            id, iconName, APP_INDICATOR_CATEGORY_APPLICATION_STATUS, iconThemePath)!
        menu = gtk_menu_new()!
        summaryItem = gtk_menu_item_new_with_label(summaryPlaceholder)!
        // Nothing to activate on the summary row — disable it so it does not read as an action.
        gtk_widget_set_sensitive(summaryItem, 0)
        gtk_menu_shell_append(UnsafeMutableRawPointer(menu).assumingMemoryBound(to: GtkMenuShell.self),
                              summaryItem)
        gtk_widget_show(summaryItem)
        appendSeparator()
        app_indicator_set_menu(indicator,
                               UnsafeMutableRawPointer(menu).assumingMemoryBound(to: GtkMenu.self))
        app_indicator_set_status(indicator, APP_INDICATOR_STATUS_ACTIVE)
    }

    /// Menu rows in insertion order, so a language change can relabel them in place. Rebuilding
    /// the menu instead would drop the AppIndicator's reference and blank the tray on some panels.
    private var items: [(widget: Widget, title: (L) -> String)] = []

    /// Re-apply every menu label in the new language.
    func relabel(_ l: L) {
        for entry in items {
            gtk_menu_item_set_label(
                UnsafeMutableRawPointer(entry.widget).assumingMemoryBound(to: GtkMenuItem.self),
                entry.title(l))
        }
    }

    /// Append a menu item. The handler lives until GTK destroys the widget (`GtkCallbackBox`).
    func addItem(_ title: String, localized: ((L) -> String)? = nil, action: @escaping () -> Void) {
        guard let item = gtk_menu_item_new_with_label(title) else { return }
        if let localized { items.append((item, localized)) }
        gtkConnect(UnsafeMutableRawPointer(item), signal: "activate", box: GtkCallbackBox(action))
        gtk_menu_shell_append(UnsafeMutableRawPointer(menu).assumingMemoryBound(to: GtkMenuShell.self),
                              item)
        gtk_widget_show(item)
    }

    func appendSeparator() {
        guard let separator = gtk_separator_menu_item_new() else { return }
        gtk_menu_shell_append(UnsafeMutableRawPointer(menu).assumingMemoryBound(to: GtkMenuShell.self),
                              separator)
        gtk_widget_show(separator)
    }

    /// The usage text shown on the panel. Written to **both** the label and the first menu row,
    /// for the reason in the type doc above.
    func setUsageText(_ text: String) {
        app_indicator_set_label(indicator, text, text)
        gtk_menu_item_set_label(
            UnsafeMutableRawPointer(summaryItem).assumingMemoryBound(to: GtkMenuItem.self), text)
    }

    /// Swap the icon — a filename inside the theme directory, without the extension.
    func setIcon(named name: String) {
        app_indicator_set_icon_full(indicator, name, "PokeTokenBar")
    }
}
#endif   // os(Linux)
