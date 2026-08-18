#if os(Linux)
import CGtk
import Foundation

/// The opt-in desktop companion — a small always-on-top window showing the sprite.
///
/// **Wayland limits what this can be.** The macOS panel remembers where you dragged it and reopens
/// there; Wayland deliberately denies clients both their own surface position and the ability to set
/// one, so the saved origin cannot be honoured and the compositor places the window. Positioning is
/// therefore the user's job via a KWin window rule. Everything else — always on top, no decorations,
/// transparent background, click to open the popover — works as on macOS.
///
/// The origin is still persisted through `UsageStore`, so nothing is lost if a future protocol
/// (or an X11 session, where it does work) can place it.
@MainActor
final class FloatingPetWindow {
    private let store: UsageStore
    private let companion: CompanionStore
    private let window: Widget
    private let image: Widget
    private var currentKey: String?
    private var isVisible = false

    init(store: UsageStore, companion: CompanionStore, onActivate: @escaping () -> Void) {
        self.store = store
        self.companion = companion

        window = gtk_window_new(GTK_WINDOW_TOPLEVEL)!
        gtk_window_set_title(asWindow(window), "PokeTokenBar pet")
        gtk_window_set_decorated(asWindow(window), 0)
        gtk_window_set_keep_above(asWindow(window), 1)
        gtk_window_set_skip_taskbar_hint(asWindow(window), 1)
        gtk_window_set_skip_pager_hint(asWindow(window), 1)
        gtk_window_set_resizable(asWindow(window), 0)
        // A utility type keeps most compositors from giving it a titlebar or a task-switcher entry.
        gtk_window_set_type_hint(asWindow(window), GDK_WINDOW_TYPE_HINT_UTILITY)

        // A button rather than a bare image: it gives keyboard focus, a hover cursor and a click
        // signal for free, and `RELIEF_NONE` keeps it from drawing a button frame around the sprite.
        let button = gtk_button_new()!
        gtk_button_set_relief(
            UnsafeMutableRawPointer(button).assumingMemoryBound(to: GtkButton.self), GTK_RELIEF_NONE)
        image = gtk_image_new()!
        gtk_container_add(asContainer(button), image)
        gtkConnect(UnsafeMutableRawPointer(button), signal: "clicked", box: GtkCallbackBox(onActivate))
        gtk_container_add(asContainer(window), button)
        enableTransparency()

        gtkConnectDeleteEvent(UnsafeMutableRawPointer(window), box: GtkCallbackBox { [weak self] in
            // Closing the pet is the same as switching it off, so the setting matches what is on
            // screen — otherwise it reappears at next launch and reads as a bug.
            self?.store.floatingPetEnabled = false
            self?.hide()
        })
    }

    /// Give the window an RGBA visual so the area around the sprite is see-through rather than a
    /// grey square. Compositor-dependent: without compositing the background falls back to opaque.
    private func enableTransparency() {
        guard let screen = gtk_widget_get_screen(window),
              let visual = gdk_screen_get_rgba_visual(screen) else { return }
        gtk_widget_set_visual(window, visual)
        gtk_widget_set_app_paintable(window, 1)
    }

    func setVisible(_ visible: Bool) {
        visible ? show() : hide()
    }

    private func show() {
        isVisible = true
        gtk_widget_show_all(window)
    }

    private func hide() {
        isVisible = false
        gtk_widget_hide(window)
    }

    /// Swap in the current companion sprite at the configured size.
    func update(spriteData: Data?, key: String) {
        guard isVisible, key != currentKey, let spriteData else { return }
        let size = Int(store.floatingPetSize)
        guard let pixbuf = SpriteRenderer.render(spriteData, size: size) else { return }
        defer { g_object_unref(UnsafeMutableRawPointer(pixbuf)) }
        gtk_image_set_from_pixbuf(asImage(image), pixbuf)
        currentKey = key
    }
}
#endif   // os(Linux)
