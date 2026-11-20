import AppKit

/// The system settings that quiet the companion's motion. One rule for every surface (popover header,
/// floating pet): Reduce Motion or Low Power Mode, each on its own, plays the short cross-fade instead of
/// the full sequence and stops the egg's periodic wobble.
struct MotionSettings: Equatable {
    var reduceMotion = false
    var lowPower = false

    var reduced: Bool { reduceMotion || lowPower }

    /// The settings right now.
    @MainActor static var system: MotionSettings {
        MotionSettings(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                       lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
    }
}
