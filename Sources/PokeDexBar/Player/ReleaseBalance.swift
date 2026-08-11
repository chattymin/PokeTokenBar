import Foundation

/// 개체 하나를 박사에게 보내면 몇 포인트인가.
///
/// **등급과 경험치, 두 가지로만 정한다.** 키운 아이일수록 값이 나가므로 정리 대상이 자연히
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

    /// `등급기본 × (진화 횟수 + 1 + 지금 단계에서 채운 경험치 비율)`, 내림.
    ///
    /// 경험치 비율의 분모는 **진화 임계**다(알 임계가 아니다). 알 발견은 최종형에만 열리는
    /// 별개의 길이고, 여기서 재는 것은 "이 단계에서 얼마나 키웠나" 다. 최종형은 알 임계까지
    /// 쌓이므로 이 비율이 1 에서 포화되는데, 최종형이라는 사실은 이미 `stageIndex` 로 값에
    /// 반영돼 있다.
    static func points(for individual: Individual) -> Int {
        let threshold = ExpBalance.threshold(grade: individual.grade,
                                             stageIndex: individual.stageIndex)
        let ratio = threshold > 0
            ? min(1, max(0, Double(individual.exp) / Double(threshold)))
            : 0
        let grown = Double(individual.stageIndex) + 1 + ratio
        return Int(Double(base(grade: individual.grade)) * grown)
    }
}
