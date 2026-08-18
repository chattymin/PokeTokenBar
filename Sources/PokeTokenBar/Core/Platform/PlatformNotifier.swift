import Foundation

#if os(macOS)
import UserNotifications
#else
import CNotify
#endif

/// System notifications — UserNotifications on macOS, libnotify (D-Bus
/// `org.freedesktop.Notifications`) on Linux.
///
/// Callers (limit alerts in `UsageStore`, companion events in `CompanionStore`) are already gated
/// on `AppEnv.isProductionInstall`, so this does not re-check. Two gates for one decision is how
/// they end up disagreeing.
enum PlatformNotifier {
    /// Request notification permission (idempotent) — once, at a user-intent moment.
    /// Linux has no such concept (showing notifications is the desktop's business), so it is a no-op.
    static func requestAuthorization() {
        #if os(macOS)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        #endif
    }

    /// Post one notification.
    /// - Parameters:
    ///   - identifier: replaces an earlier notification with the same key, so a limit window only
    ///     ever occupies one slot.
    ///   - sound: whether to play a sound.
    ///   - critical: urgency. **Deliberately separate from `sound`** — on Linux CRITICAL means
    ///     "stays until the user dismisses it" (KDE never auto-dismisses), so attaching it to
    ///     companion events, which only want a sound, would leave hatch alerts parked on screen.
    ///     macOS has no equivalent concept and ignores it.
    static func post(identifier: String, title: String, body: String, sound: Bool, critical: Bool) {
        #if os(macOS)
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = sound ? .default : nil
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
        #else
        guard initializeIfNeeded() else { return }
        guard let notification = notify_notification_new(title, body, nil) else { return }
        defer { g_object_unref(notification) }
        notify_notification_set_urgency(
            notification, critical ? NOTIFY_URGENCY_CRITICAL : NOTIFY_URGENCY_NORMAL)
        // Carries over the replace-by-identifier meaning from macOS so limit alerts update in
        // place instead of stacking. Not a standard hint — support varies by notification daemon
        // (unsupported ones simply show a new notification), but where it works it stops the
        // panel filling up with one alert per limit window.
        notify_notification_set_hint_string(notification, "x-canonical-private-synchronous", identifier)
        if sound {
            notify_notification_set_hint_string(
                notification, "sound-name", critical ? "dialog-warning" : "message-new-instant")
        }
        notify_notification_show(notification, nil)
        #endif
    }

    #if !os(macOS)
    /// `notify_init` runs once per process. On failure (no D-Bus — headless, container) we give up
    /// on notifications quietly.
    nonisolated(unsafe) private static var initialized: Bool?
    private static func initializeIfNeeded() -> Bool {
        if let initialized { return initialized }
        let ok = notify_init("PokeTokenBar") != 0
        initialized = ok
        if !ok { AppLog.write("notify_init failed — notifications disabled (no D-Bus session?)") }
        return ok
    }
    #endif
}
