import Foundation

/// How far along an egg looks, as four tiers that drive its periodic wobble and the line
/// the sprite shows when tapped. Pure: progress in, tier out.
enum EggIncubationTier: Int, CaseIterable {
    case early = 1, moving, sounds, imminent

    /// Tier lower bounds on hatch progress (1.0 = threshold reached).
    private static let movingStart = 0.4
    private static let soundsStart = 0.7
    private static let imminentStart = 0.9

    static func tier(progress: Double) -> EggIncubationTier {
        if progress >= imminentStart { return .imminent }
        if progress >= soundsStart { return .sounds }
        if progress >= movingStart { return .moving }
        return .early
    }

    /// Pause between one-shot wobbles; nil = the egg stays still.
    var wobbleInterval: Duration? {
        switch self {
        case .early: return nil
        case .moving: return .seconds(20)
        case .sounds: return .seconds(8)
        case .imminent: return .seconds(3)
        }
    }

    /// Sleeps `interval`, wobbles once, repeats; returns when a sleep throws (the task was cancelled). The one
    /// loop behind both surfaces' periodic wobbles. `sleep` is injectable so tests do not wait for real seconds.
    @MainActor
    static func wobbleLoop(every interval: Duration,
                           sleep: (Duration) async throws -> Void = { try await Task.sleep(for: $0, tolerance: .seconds(1)) },
                           wobble: () -> Void) async {
        while true {
            do { try await sleep(interval) } catch { return }
            wobble()
        }
    }

    func text(_ l: L) -> String {
        switch self {
        case .early: return l.eggTierEarly
        case .moving: return l.eggTierMoving
        case .sounds: return l.eggTierSounds
        case .imminent: return l.eggTierImminent
        }
    }
}
