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

    /// 알 하나를 발견할 값어치. 등급이 오를 때마다 두 배 — 진화 임계와 같은 비율이되
    /// **자릿수가 다르다**(커먼 기준 진화 한 단계의 10배).
    ///
    /// 왜 진화보다 훨씬 비싼가: 진화는 어차피 갈 길을 가는 것이고, 이 알은 **종을 확정해서**
    /// 부른다. 상점 뽑기(1000만 토큰)가 무엇이 나올지 모르는 값이라면, 이쪽은 무엇이 나올지
    /// 아는 값이다 — 커먼 알 하나가 뽑기 50번어치다. 다 키운 아이를 곁에 오래 두는 것에만
    /// 열리는 길이라, 흔하면 그 무게가 사라진다.
    ///
    /// 진화 임계에서 파생시키지 않고 표를 따로 두는 이유: 둘의 근거가 다르다. 진화는 "얼마나
    /// 써야 다음 단계인가", 이건 "확정 종 하나가 얼마인가" 다. 한쪽을 조정할 때 다른 쪽이
    /// 딸려 움직이면 안 된다.
    static func eggThreshold(grade: Grade) -> Int {
        switch grade {
        case .common: 500_000_000
        case .rare: 1_000_000_000
        case .epic: 2_000_000_000
        case .legendary: 4_000_000_000
        }
    }
}
