#if os(Linux)
import CGtk
import Dispatch
import Foundation

/// Lets the GTK main loop and Swift concurrency (MainActor) share one thread.
///
/// **The problem.** Both want to be "the loop that owns the main thread". Calling `gtk_main()`
/// blocks inside it, so libdispatch's main queue never runs and none of the `@MainActor` work in
/// `UsageStore` / `CompanionStore` executes. Running only `dispatchMain()` has the mirror problem:
/// GTK events go unprocessed and the tray menu stops responding. Taking Core off MainActor
/// entirely was rejected — that splits code shared with macOS.
///
/// **What we do.** libdispatch is the primary loop (`dispatchMain()`), and GTK is pumped from a
/// repeating timer on the main queue. Given that one of the two loops has to yield, keeping Swift
/// concurrency alive is what lets the shared code stay shared.
///
/// **The cost — idle wakeups.** The pump wakes the CPU at its interval. This repository has
/// already been burned once by wakeup amplification from an always-on animation
/// (`defect-log` §에너지 / "Energy"), so the default is deliberately slack and only tightens when a window is
/// up: 50ms (20Hz) for the tray alone, 16ms (60Hz) with a window. 50ms is imperceptible on a
/// menu click.
///
/// The better fix is Swift 6's custom main executor, putting MainActor directly on the GLib
/// context and removing the pump altogether — worth revisiting once the tray is settled
/// (roadmap Phase 8).
enum GtkRuntime {
    /// Pump interval with no window open. Only the tray menu has to respond, so it runs slack.
    private static let idleInterval: DispatchTimeInterval = .milliseconds(50)
    /// Interval while a window (popover, floating pet) is visible.
    private static let activeInterval: DispatchTimeInterval = .milliseconds(16)

    @MainActor private static var pumping = false

    /// True while a window is up, which tightens the pump. The frontend updates it on show/hide.
    @MainActor static var hasVisibleWindow = false

    /// `gtk_init` — false when there is no display (TTY, SSH). The caller explains and exits.
    static func initialize() -> Bool {
        // The desktop matches a window to its `.desktop` file by app id / WM_CLASS, and that is what
        // gives the task bar an icon and a name. GTK derives it from the executable's filename by
        // default, so a dev run (`PokeTokenBar`) and the installed binary (`poketokenbar`) would
        // claim different identities and only one of them would match `poketokenbar.desktop`.
        // Pinning it makes both resolve.
        g_set_prgname("poketokenbar")
        gdk_set_program_class("poketokenbar")
        guard gtk_init_check(nil, nil) != 0 else { return false }
        applyDefaultWindowIcon()
        return true
    }

    /// Give every window the app icon.
    ///
    /// Falls back to the sprite the tray already generated when the themed icon is not installed
    /// (a dev run out of the build directory), because a blank task-bar entry reads as a broken app.
    private static func applyDefaultWindowIcon() {
        if let theme = gtk_icon_theme_get_default(),
           gtk_icon_theme_has_icon(theme, "poketokenbar") != 0 {
            gtk_window_set_default_icon_name("poketokenbar")
            return
        }
        let fallback = PlatformPaths.appDirectory("tray").appendingPathComponent("companion-egg.png")
        if FileManager.default.fileExists(atPath: fallback.path) {
            gtk_window_set_default_icon_from_file(fallback.path, nil)
        }
    }

    /// Starts pumping GTK events on the main queue. Call once, before `dispatchMain()`.
    static func startPumpFromMainQueue() {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard !pumping else { return }
                pumping = true
                schedule()
            }
        }
    }

    @MainActor private static func schedule() {
        let interval = hasVisibleWindow ? activeInterval : idleInterval
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
            MainActor.assumeIsolated {
                // Drain only what is pending; never block. Passing `true` would stall the main
                // queue whenever GTK has no events.
                while gtk_events_pending() != 0 {
                    _ = gtk_main_iteration_do(0)
                }
                schedule()
            }
        }
    }
}

/// A box that carries a Swift closure through a C callback.
///
/// GTK signals hand back a single `gpointer`. A closure cannot cross into C directly, so it is
/// wrapped in a class whose lifetime we hold manually via `Unmanaged` — the box has to outlive the
/// widget, and leaving it to ARC means the first click calls into freed memory.
final class GtkCallbackBox {
    let run: () -> Void
    init(_ run: @escaping () -> Void) { self.run = run }

    /// An opaque pointer holding a +1 retain. GTK calls the matching release when the widget dies.
    var opaque: UnsafeMutableRawPointer { Unmanaged.passRetained(self).toOpaque() }
}

/// Connect one signal. `g_signal_connect` is a C macro and unavailable to Swift, so this calls
/// the real function underneath it.
@discardableResult
func gtkConnect(
    _ instance: UnsafeMutableRawPointer,
    signal: String,
    box: GtkCallbackBox
) -> gulong {
    let callback: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void = {
        _, data in
        guard let data else { return }
        Unmanaged<GtkCallbackBox>.fromOpaque(data).takeUnretainedValue().run()
    }
    let destroy: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<GClosure>?) -> Void = {
        data, _ in
        guard let data else { return }
        Unmanaged<GtkCallbackBox>.fromOpaque(data).release()
    }
    return g_signal_connect_data(
        instance, signal,
        unsafeBitCast(callback, to: GCallback.self),
        box.opaque,
        destroy,
        GConnectFlags(rawValue: 0))
}
/// Connect a window's `delete-event` (the close button).
///
/// Separate from `gtkConnect` because this signal's handler returns `gboolean`, and returning TRUE
/// is what tells GTK "handled — do not destroy". A tray app must hide rather than destroy: the
/// process outlives the window, and a destroyed one leaves every later `show()` pointing at freed
/// widgets.
@discardableResult
func gtkConnectDeleteEvent(_ instance: UnsafeMutableRawPointer, box: GtkCallbackBox) -> gulong {
    let callback: @convention(c) (
        UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?
    ) -> gboolean = { _, _, data in
        guard let data else { return 0 }
        Unmanaged<GtkCallbackBox>.fromOpaque(data).takeUnretainedValue().run()
        return 1   // handled: suppress the default destroy
    }
    let destroy: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<GClosure>?) -> Void = {
        data, _ in
        guard let data else { return }
        Unmanaged<GtkCallbackBox>.fromOpaque(data).release()
    }
    return g_signal_connect_data(
        instance, "delete-event",
        unsafeBitCast(callback, to: GCallback.self),
        box.opaque, destroy, GConnectFlags(rawValue: 0))
}

#endif   // os(Linux)
