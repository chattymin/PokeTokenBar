import Foundation

/// 자기 라인의 알을 하나 불러오는 표.
///
/// **왜 있나:** 최종진화체는 경험치를 계속 버는데 쓸 데가 없다 — `evolutionChoices` 가 빈
/// 배열이라 `canEvolve` 가 참이 되어도 갈 곳이 없다. 다 키운 아이일수록 곁에 둘 이유가 없어지는,
/// 방향이 거꾸로 된 유인이었다. 이 표가 그 경험치를 다시 흐르게 한다.
///
/// **왜 등급을 같이 들고 다니나:** 종→등급 판정(`EggBalance` 의 종 등급)은 네트워크로 오는
/// 베이스 인덱스를 요구한다. 쓰는 시점에 그걸 요구하면 오프라인에서 교환권을 못 쓴다. 지급하는
/// 시점에는 개체가 손에 있으므로 `Individual.grade`(태어날 때 그 라인에서 정해진 값)를 받아 둔다.
struct EggVoucher: Codable, Sendable, Equatable {
    /// 불러올 종 — 그 개체의 `baseID` 다. 리자몽은 파이리를, 라프라스는 라프라스를 부른다.
    var baseID: Int
    /// 알의 등급. 부화 시간이 여기서 나온다.
    var grade: Grade

    /// 교환권 한 장 값. **진화 한 단계와 같은 환율**(`stageIndex: 0` 의 기본값)이다 —
    /// 새 환율을 발명하지 않는 것이 요점이다. 최종형의 진화 임계(기본값 × 3)를 쓰지 않는 이유는,
    /// 그게 "갈 곳도 없는데 세 배를 내라"가 되기 때문이다.
    static func threshold(grade: Grade) -> Int {
        ExpBalance.threshold(grade: grade, stageIndex: 0)
    }

    /// 말이 되는 값인가. 관대 디코딩의 짝 — 종 번호가 1 미만이면 스프라이트도 이름도 없다.
    var isSane: Bool { baseID >= 1 }
}
