import Foundation

#if os(macOS)
import AppKit
#endif

/// Sleep and display-off events — used to pause polling (which spawns subprocesses) and save battery.
enum PlatformPowerEvents {
    /// - Parameters:
    ///   - onWake: resumed from system sleep — refresh immediately.
    ///   - onScreenSleep: display turned off — stop polling.
    ///   - onScreenWake: display turned on — resume polling and refresh.
    static func observe(
        onWake: @escaping () -> Void,
        onScreenSleep: @escaping () -> Void,
        onScreenWake: @escaping () -> Void
    ) {
        #if os(macOS)
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            onWake()
        }
        center.addObserver(
            forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main
        ) { _ in onScreenSleep() }
        center.addObserver(
            forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main
        ) { _ in onScreenWake() }
        #else
        // The subscription itself lives in the Linux frontend, which owns the GLib main loop GDBus
        // needs to deliver signals. Keeping it out of Core is what stops Core depending on GTK.
        // If nothing installed an observer (tests, headless), polling simply never pauses.
        linuxObserver?(onWake, onScreenSleep, onScreenWake)
        #endif
    }

    #if !os(macOS)
    /// Installed by the Linux frontend at startup, before any store is built.
    nonisolated(unsafe) static var linuxObserver: (
        (@escaping () -> Void, @escaping () -> Void, @escaping () -> Void) -> Void
    )?
    #endif
}
