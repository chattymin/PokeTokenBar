import Foundation

/// How fast an always-on sprite is allowed to animate.
///
/// Gen-V sprites carry native delays as low as 0.02s. Honouring those on a surface that is on
/// screen all day (the macOS menu bar, the Linux tray, the floating pet) means recompositing ~50
/// times a second forever, and this repository has already paid for that once in idle wakeups
/// (`defect-log` §에너지 / "Energy"). Transient surfaces — the popover, which is only open while
/// someone is looking at it — keep the native rate by passing a floor of 0.
enum SpriteAnimationPolicy {
    /// ≈2.5fps. Slow enough to cost nothing at idle, fast enough to still read as movement.
    static let idleFrameFloor: TimeInterval = 0.4

    /// The delay to actually wait for a frame, given its native delay and a floor.
    static func frameDelay(base: TimeInterval, floor: TimeInterval) -> TimeInterval {
        max(base, floor)
    }
}
