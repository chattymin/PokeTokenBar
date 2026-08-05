import Foundation

/// 진화 임계. 파트너는 토큰 사용량만큼 경험치를 얻으므로 이 값이 곧 "얼마나 써야 진화하나"다.
enum ExpBalance {
    /// 등급·단계별 임계. 2→3단계는 1→2단계의 3배 — 뒤로 갈수록 무겁게.
    static func threshold(grade: Grade, stageIndex: Int) -> Int {
        let base: Int = switch grade {
        case .common: 50_000_000
        case .rare: 100_000_000
        case .epic: 200_000_000
        case .legendary: 400_000_000
        }
        return stageIndex <= 0 ? base : base * 3
    }
}
