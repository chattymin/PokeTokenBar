#if os(Linux)
import CGtk
import Foundation

/// Sleep and screen-blank signals, over the session and system buses.
///
/// This is the Linux half of `PlatformPowerEvents`. It lives in the frontend because GDBus delivers
/// signals through the GLib main context, which only exists once the GTK loop is running.
///
/// Two sources, because no single one covers both cases:
/// - `org.freedesktop.login1.Manager.PrepareForSleep` (system bus) — suspend and resume. The signal
///   carries `true` on the way down and `false` on the way back, so only the `false` edge is a wake.
/// - `org.freedesktop.ScreenSaver.ActiveChanged` (session bus) — the screen blanking or unblanking,
///   which is what macOS's `screensDidSleep` actually corresponds to. KDE and GNOME both implement it.
enum PowerEvents {
    /// Kept alive for the process lifetime — dropping the connections cancels the subscriptions.
    nonisolated(unsafe) private static var connections: [OpaquePointer] = []
    /// Retained callback boxes; GDBus keeps only the raw pointer.
    nonisolated(unsafe) private static var boxes: [SignalBox] = []

    final class SignalBox {
        let handle: (Bool) -> Void
        init(_ handle: @escaping (Bool) -> Void) { self.handle = handle }
    }

    static func install() {
        PlatformPowerEvents.linuxObserver = { onWake, onScreenSleep, onScreenWake in
            subscribe(
                bus: G_BUS_TYPE_SYSTEM,
                sender: "org.freedesktop.login1",
                interface: "org.freedesktop.login1.Manager",
                signal: "PrepareForSleep"
            ) { goingToSleep in
                // Only the resume edge matters: on the way down there is nothing left to refresh.
                if !goingToSleep { onWake() }
            }

            subscribe(
                bus: G_BUS_TYPE_SESSION,
                sender: nil,   // KDE and GNOME own this name from different services
                interface: "org.freedesktop.ScreenSaver",
                signal: "ActiveChanged"
            ) { screenSaverActive in
                screenSaverActive ? onScreenSleep() : onScreenWake()
            }
        }
    }

    private static func subscribe(
        bus: GBusType, sender: String?, interface: String, signal: String,
        handler: @escaping (Bool) -> Void
    ) {
        guard let connection = g_bus_get_sync(bus, nil, nil) else {
            AppLog.write("power events: no \(interface) bus — sleep/blank pauses disabled")
            return
        }
        connections.append(connection)
        let box = SignalBox(handler)
        boxes.append(box)

        let callback: @convention(c) (
            OpaquePointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafePointer<CChar>?,
            UnsafePointer<CChar>?, OpaquePointer?, UnsafeMutableRawPointer?
        ) -> Void = { _, _, _, _, _, parameters, data in
            guard let data, let parameters else { return }
            // Every signal we subscribe to is `(b)`. `g_variant_get_child` is variadic and out of
            // reach from Swift, so the child is taken as a value and read directly.
            guard let child = g_variant_get_child_value(parameters, 0) else { return }
            defer { g_variant_unref(child) }
            let flag = g_variant_get_boolean(child) != 0
            Unmanaged<SignalBox>.fromOpaque(data).takeUnretainedValue().handle(flag)
        }

        g_dbus_connection_signal_subscribe(
            connection, sender, interface, signal, nil, nil,
            GDBusSignalFlags(rawValue: 0), callback,
            Unmanaged.passUnretained(box).toOpaque(), nil)
    }
}
#endif   // os(Linux)
