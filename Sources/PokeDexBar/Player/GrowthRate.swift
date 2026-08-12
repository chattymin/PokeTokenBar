import Foundation

/// 본가의 경험치 성장 곡선 여섯 가지. **순수 표**라 테스트로 잠근다.
///
/// 앱의 `Individual` 이 이 값을 들고 다닌다(라인이 아니라) — 레벨 계산은 사용량 갱신 경로에서
/// 매번 일어나는데 그 자리에는 `EvoLine`(네트워크)이 없기 때문이다. 성격·등급과 같은 취급이다.
enum GrowthRate: String, Codable, Sendable, CaseIterable {
    case erratic, fast, mediumFast, mediumSlow, slow, fluctuating

    static let maxLevel = 100

    /// PokéAPI `pokemon-species.growth_rate.name` → 이 열거형.
    /// PokéAPI 의 growth-rate 리소스가 여섯 개라 이 표가 전부다. 모르는 값은 가장 흔한
    /// `mediumFast` 로 떨어뜨린다 — 데이터가 낯설다고 화면이 멈추면 안 된다.
    static func fromAPI(_ name: String) -> GrowthRate {
        switch name {
        case "slow-then-very-fast": .erratic
        case "fast": .fast
        case "medium": .mediumFast
        case "medium-slow": .mediumSlow
        case "slow": .slow
        case "fast-then-very-slow": .fluctuating
        default: .mediumFast
        }
    }

    /// 그 레벨에 도달하는 데 필요한 **누적** 경험치. 본가 공식 그대로이며 정수 내림이다.
    ///
    /// `level <= 1` 을 0으로 잘라내는 것이 중요하다 — `mediumSlow` 공식은 n=1 에서 −53.8 을
    /// 내고, 그 음수가 그대로 나가면 `level(forExp:)` 이 통째로 어긋난다.
    func totalExp(at level: Int) -> Int {
        guard level > 1 else { return 0 }
        let n = min(level, Self.maxLevel)
        let cube = n * n * n
        switch self {
        case .fast: return 4 * cube / 5
        case .mediumFast: return cube
        case .slow: return 5 * cube / 4
        case .mediumSlow:
            return Int(1.2 * Double(cube)) - 15 * n * n + 100 * n - 140
        case .erratic:
            if n < 50 { return cube * (100 - n) / 50 }
            if n < 68 { return cube * (150 - n) / 100 }
            if n < 98 { return cube * ((1911 - 10 * n) / 3) / 500 }
            return cube * (160 - n) / 100
        case .fluctuating:
            if n < 15 { return cube * ((n + 1) / 3 + 24) / 50 }
            if n < 36 { return cube * (n + 14) / 50 }
            return cube * (n / 2 + 32) / 50
        }
    }

    /// 누적 경험치 → 레벨. `totalExp(at:)` 의 역이며 100에서 멈춘다.
    /// 100번 도는 선형 탐색이라 이분 탐색을 쓸 이유가 없다(호출 빈도가 화면 갱신 수준이다).
    func level(forExp exp: Int) -> Int {
        guard exp > 0 else { return 1 }
        var result = 1
        for level in 2...Self.maxLevel where totalExp(at: level) <= exp { result = level }
        return result
    }
}
