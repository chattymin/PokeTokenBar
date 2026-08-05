import Foundation

/// 부화 중인 알. 종과 이로치 여부는 **뽑는 순간** 정해 두고(스프라이트를 미리 받으려고)
/// 부화 때 공개한다.
struct Egg: Identifiable, Codable, Sendable, Equatable {
    var id = UUID()
    var grade: Grade
    var speciesID: Int
    var shiny: Bool
    var startedAt: Date
    var hatchesAt: Date

    func isReady(at now: Date) -> Bool { now >= hatchesAt }

    /// 남은 시간. 이미 지났으면 0 — 음수가 화면에 새지 않게.
    func remaining(at now: Date) -> TimeInterval {
        max(0, hatchesAt.timeIntervalSince(now))
    }
}
