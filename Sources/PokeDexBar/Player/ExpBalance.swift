import Foundation

/// 파트너 경험치·알 계량기의 환율표. 진화 자체는 더 이상 경험치 임계가 아니라 조건
/// (레벨·도구·친밀도 등, `PlayerStore+Evolution`)이 게이트다 — 여기 남은 것은 경험치가
/// 어떻게 쌓이는지와, 알 하나를 부르는 값어치뿐이다.
enum ExpBalance {
    /// 토큰 몇 개가 1EXP 인가. **이 앱의 손잡이**이고, 곡선은 본가 값 그대로다.
    /// 500인 근거: 실측 하루 평균 3.65억 토큰에서 `mediumFast` 만렙(5억 토큰)이 약 1.5일.
    static let tokensPerExp = 500

    /// 경험치 사탕 하나가 주는 EXP. 예전 값(1억 토큰)을 환율로 나눈 값이라 **값어치가 안 바뀐다**.
    static let candyExp = 200_000

    /// 알 하나를 발견할 값어치. 등급이 오를 때마다 두 배.
    ///
    /// 왜 비싼가: 상점 뽑기(1000만 토큰)가 무엇이 나올지 모르는 값이라면, 이쪽은 무엇이 나올지
    /// 아는 값이다 — 커먼 알 하나가 뽑기 50번어치다. 다 키운 아이를 곁에 오래 두는 것에만
    /// 열리는 길이라, 흔하면 그 무게가 사라진다.
    static func eggThreshold(grade: Grade) -> Int {
        switch grade {
        case .common: 500_000_000
        case .rare: 1_000_000_000
        case .epic: 2_000_000_000
        case .legendary: 4_000_000_000
        }
    }
}
