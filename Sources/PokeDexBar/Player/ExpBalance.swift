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

    /// 알 하나를 발견할 값어치. **진화 한 단계와 같은 환율**(`stageIndex: 0` 의 기본값)이다 —
    /// 최종형에 갇힌 경험치가 새 환율이 아니라 진화와 같은 값으로 다시 흐르는 것이 요점이다.
    /// 최종형의 진화 임계(기본값 × 3)를 쓰지 않는 이유는, 그게 "갈 곳도 없는데 세 배를 내라"가
    /// 되기 때문이다.
    static func eggThreshold(grade: Grade) -> Int {
        threshold(grade: grade, stageIndex: 0)
    }
}
