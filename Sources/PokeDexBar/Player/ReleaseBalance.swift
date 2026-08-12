import Foundation

/// 개체 하나를 박사에게 보내면 몇 포인트인가.
///
/// **등급과 레벨, 두 가지로만 정한다.** 키운 아이일수록 값이 나가므로 정리 대상이 자연히
/// "안 키운 중복" 이 된다 — 이 기능이 노리는 방향이다.
enum ReleaseBalance {
    /// 포인트 상한. 산술 안전용이지 게임 규칙이 아니다 — 정상 플레이로는 근처도 안 간다
    /// (전설 최종형 하나가 160 이다). 봉인을 깬 세이브의 `Int.max` 가 이후 덧셈에서 오버플로
    /// 트랩을 내는 것을 경계 한 곳에서 막는다.
    static let maxPoints = 1_000_000

    /// 등급기본.
    static func base(grade: Grade) -> Int {
        switch grade {
        case .common: 2
        case .rare: 5
        case .epic: 12
        case .legendary: 40
        }
    }

    /// `등급기본 × (진화 횟수 + 1 + 레벨/100)`, 내림.
    ///
    /// 예전에는 "지금 단계에서 채운 경험치 비율" 이었는데, 경험치가 레벨이 되면서 **레벨 자체가
    /// 얼마나 키웠나** 를 곧바로 말해 준다. 100레벨이 한 단계를 통째로 더 얹는 것과 같아
    /// 자릿수는 예전과 같다.
    static func points(for individual: Individual) -> Int {
        let grown = Double(individual.stageIndex) + 1
            + Double(individual.level) / Double(GrowthRate.maxLevel)
        return Int(Double(base(grade: individual.grade)) * grown)
    }
}
