#if os(Linux)
import CGtk
import Foundation

/// Settings — the Linux counterpart of the macOS settings sheet.
///
/// Every control writes straight through to `UsageStore` / `CompanionStore`, which persist to
/// `UserDefaults` on set. There is no apply/cancel step, matching macOS: a toggle that needs
/// confirming is a toggle people leave in the wrong state.
@MainActor
final class SettingsWindow {
    private let store: UsageStore
    private let companion: CompanionStore
    private let window: Widget
    private let content: Widget
    private var isVisible = false
    /// Set while rebuilding, so programmatic widget updates do not echo back as user edits and
    /// fight the value being restored.
    private var isPopulating = false

    init(store: UsageStore, companion: CompanionStore) {
        self.store = store
        self.companion = companion

        window = gtk_window_new(GTK_WINDOW_TOPLEVEL)!
        gtk_window_set_title(asWindow(window), "PokeTokenBar — Settings")
        gtk_window_set_default_size(asWindow(window), 420, 620)
        gtk_window_set_position(asWindow(window), GTK_WIN_POS_CENTER)

        let scroller = gtk_scrolled_window_new(nil, nil)!
        gtk_scrolled_window_set_policy(
            UnsafeMutableRawPointer(scroller).assumingMemoryBound(to: GtkScrolledWindow.self),
            GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC)
        content = Gtk.box(GTK_ORIENTATION_VERTICAL, spacing: 10)
        Gtk.margins(content, top: 12, bottom: 12, start: 12, end: 12)
        gtk_container_add(asContainer(scroller), content)
        gtk_container_add(asContainer(window), scroller)

        gtkConnectDeleteEvent(UnsafeMutableRawPointer(window),
                              box: GtkCallbackBox { [weak self] in self?.hide() })
    }

    func show() {
        isVisible = true
        GtkRuntime.hasVisibleWindow = true
        rebuild()
        gtk_widget_show_all(window)
        gtk_window_present(asWindow(window))
    }

    func hide() {
        isVisible = false
        GtkRuntime.hasVisibleWindow = false
        gtk_widget_hide(window)
    }

    private func rebuild() {
        isPopulating = true
        defer { isPopulating = false }
        Gtk.clear(content)
        let l = companion.l

        section(l.generalSectionTitle) { box in
            self.dropdown(box, l.language, AppLanguage.allCases.map(\.label),
                          selected: AppLanguage.allCases.firstIndex(of: self.companion.language) ?? 0) { index in
                self.companion.setLanguage(AppLanguage.allCases[index])
                // The whole UI is localised at build time, so a language change means rebuilding
                // every visible surface — not just this window.
                self.rebuild()
                self.onLanguageChange?()
            }
            let presets = UsageStore.intervalPresets
            self.dropdown(box, l.refreshInterval, presets.map { l.intervalLabel($0.value) },
                          selected: presets.firstIndex { $0.value == self.store.refreshInterval } ?? 0) { index in
                self.store.refreshInterval = presets[index].value
            }
            self.dropdown(box, l.limitDisplayModeLabel, [l.limitDisplayUsed, l.limitDisplayRemaining],
                          selected: self.store.limitDisplayMode == .used ? 0 : 1) { index in
                self.store.limitDisplayMode = index == 0 ? .used : .remaining
            }
            self.toggle(box, l.launchAtLogin, LoginItem.isEnabled) { on in
                do { try LoginItem.setEnabled(on) } catch {
                    AppLog.write("autostart toggle failed: \(error)")
                }
            }
        }

        section(l.menuBarSectionTitle) { box in
            self.toggle(box, l.todayTokensShort, self.store.showTokensInMenu) { self.store.showTokensInMenu = $0 }
            self.toggle(box, l.todayCost, self.store.showCostInMenu) { self.store.showCostInMenu = $0 }
            self.toggle(box, l.limitPercent, self.store.showLimitInMenu) { self.store.showLimitInMenu = $0 }
        }

        section(l.floatingPetSectionTitle) { box in
            self.toggle(box, l.floatingPetEnableLabel, self.store.floatingPetEnabled) {
                self.store.floatingPetEnabled = $0
                self.onFloatingPetChange?()
            }
            self.toggle(box, l.floatingPetBubbleAlertsLabel, self.store.floatingPetBubbleAlerts) {
                self.store.floatingPetBubbleAlerts = $0
            }
        }

        section(l.notificationsSection) { box in
            self.toggle(box, l.limitNotificationsLabel, self.store.limitNotifications) {
                self.store.limitNotifications = $0
            }
            self.toggle(box, l.companionNotificationsLabel, self.store.companionNotifications) {
                self.store.companionNotifications = $0
            }
            self.toggle(box, l.statusChecksLabel, self.store.statusChecksEnabled) {
                self.store.statusChecksEnabled = $0
            }
        }

        section(l.updateSectionTitle) { box in
            self.toggle(box, l.updateNotificationsLabel, self.store.updateNotificationsEnabled) {
                self.store.updateNotificationsEnabled = $0
            }
        }

        section(l.aboutSupportSectionTitle) { box in
            let version = Gtk.label("<span size='small'>PokeTokenBar \(Gtk.escape(AppVersion.current))</span>")
            Gtk.addClass(version, "ptb-muted")
            Gtk.pack(box, version)
            self.button(box, l.showLogFile) { PlatformOpener.reveal(AppLog.logFileURL) }
            self.button(box, l.reportProblem) {
                let body = l.reportMailBody(
                    version: AppVersion.current,
                    os: ProcessInfo.processInfo.operatingSystemVersionString)
                if let url = SupportMail.mailtoURL(
                    subject: l.reportMailSubject(AppVersion.current), body: body) {
                    PlatformOpener.open(url)
                }
            }
        }
    }

    /// Called after the language changes, so the tray and popover relabel too.
    var onLanguageChange: (() -> Void)?
    /// Called when the floating-pet toggle flips, so the pet window appears or goes away at once.
    var onFloatingPetChange: (() -> Void)?

    // MARK: building blocks

    private func section(_ title: String, _ body: (Widget) -> Void) {
        let card = Gtk.box(GTK_ORIENTATION_VERTICAL, spacing: 8)
        Gtk.addClass(card, "ptb-card")
        let heading = Gtk.label(Gtk.escape(title))
        Gtk.addClass(heading, "ptb-section")
        Gtk.pack(card, heading)
        body(card)
        Gtk.pack(content, card)
    }

    private func row(_ parent: Widget, _ title: String) -> Widget {
        let row = Gtk.box(GTK_ORIENTATION_HORIZONTAL, spacing: 10)
        let label = Gtk.label("<span size='small'>\(Gtk.escape(title))</span>", wrap: true)
        gtk_widget_set_hexpand(label, 1)
        Gtk.pack(row, label, expand: true)
        Gtk.pack(parent, row)
        return row
    }

    private func toggle(
        _ parent: Widget, _ title: String, _ value: Bool, _ onChange: @escaping (Bool) -> Void
    ) {
        let container = row(parent, title)
        let toggle = gtk_switch_new()!
        gtk_switch_set_active(
            UnsafeMutableRawPointer(toggle).assumingMemoryBound(to: GtkSwitch.self), value ? 1 : 0)
        gtk_widget_set_valign(toggle, GTK_ALIGN_CENTER)
        gtkConnect(UnsafeMutableRawPointer(toggle), signal: "notify::active",
                   box: GtkCallbackBox { [weak self] in
                       guard let self, !self.isPopulating else { return }
                       let active = gtk_switch_get_active(
                           UnsafeMutableRawPointer(toggle).assumingMemoryBound(to: GtkSwitch.self)) != 0
                       onChange(active)
                   })
        Gtk.pack(container, toggle)
    }

    private func dropdown(
        _ parent: Widget, _ title: String, _ options: [String], selected: Int,
        _ onChange: @escaping (Int) -> Void
    ) {
        let container = row(parent, title)
        let combo = gtk_combo_box_text_new()!
        let comboText = UnsafeMutableRawPointer(combo).assumingMemoryBound(to: GtkComboBoxText.self)
        for option in options { gtk_combo_box_text_append_text(comboText, option) }
        gtk_combo_box_set_active(
            UnsafeMutableRawPointer(combo).assumingMemoryBound(to: GtkComboBox.self), Int32(selected))
        gtk_widget_set_valign(combo, GTK_ALIGN_CENTER)
        gtkConnect(UnsafeMutableRawPointer(combo), signal: "changed",
                   box: GtkCallbackBox { [weak self] in
                       guard let self, !self.isPopulating else { return }
                       let index = gtk_combo_box_get_active(
                           UnsafeMutableRawPointer(combo).assumingMemoryBound(to: GtkComboBox.self))
                       guard index >= 0 else { return }
                       onChange(Int(index))
                   })
        Gtk.pack(container, combo)
    }

    private func button(_ parent: Widget, _ title: String, _ action: @escaping () -> Void) {
        let button = gtk_button_new_with_label(title)!
        gtk_widget_set_halign(button, GTK_ALIGN_START)
        gtkConnect(UnsafeMutableRawPointer(button), signal: "clicked", box: GtkCallbackBox(action))
        Gtk.pack(parent, button)
    }
}
#endif   // os(Linux)
