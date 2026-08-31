import Foundation

/// 두드리면 반응하는 겉모습.
///
/// 원작에서 이 아이들은 **배틀 중에** 모습이 바뀐다. 이 앱엔 배틀이 없지만, 사용자가 펫에게
/// 할 수 있는 물리적 행동이 하나 있다 — 누르는 것. 그래서 트리거를 지어낸 게 아니라 옮겼다.
///
/// **회복은 파트너에서 내려올 때다.** 빙큐보는 원작에서도 배틀이 끝나면 돌아오므로 그대로 맞고,
/// 따라큐는 원작에서 *회복해야* 돌아온다 — 이 앱엔 HP도 회복도 없어 어떤 규칙을 써도 근사이고,
/// 그중 "곁에서 내려오면 낫는다"가 가장 자연스러웠다. 메테노의 껍질과 약어리의 무리도 같은 규칙을
/// 따른다(원작에서도 배틀이 끝나면 원래대로 돌아온다).
///
/// 날씨로 회복하는 경로(빙큐보의 싸라기눈)는 뺐다 — 앱에 날씨 소스가 없고, 붙이면 외부 의존과
/// 위치정보가 따라온다(캐스퐁을 안 넣은 것과 같은 이유).
enum BrokenForm {
    /// 두드리기 전후의 모습. **양쪽 다 옵셔널인 이유는 방향이 종마다 반대이기 때문이다.**
    /// 따라큐는 멀쩡할 때가 종 기본 그림이고 깨지면 특수 슬러그인데, 메테노는 그 반대다 —
    /// 평소엔 유성 껍질(`minior-meteor`)을 쓰고 있고 깨지면 기본 그림(분홍 코어)이 드러난다
    /// (스프라이트를 눈으로 확인했다). 한쪽만 담는 표로는 메테노를 거꾸로 그리게 된다.
    struct Reaction: Sendable, Equatable {
        /// 아직 안 두드렸을 때. nil 이면 종 기본 그림.
        let intact: String?
        /// 두드린 뒤. nil 이면 종 기본 그림.
        let tapped: String?
    }

    static let reactions: [Int: Reaction] = [
        // 따라큐 — 탈이 깨진 모습.
        778: Reaction(intact: nil, tapped: "mimikyu-busted"),
        // 빙큐보 — 얼음머리가 깨져 나이스페이스가 된다.
        875: Reaction(intact: nil, tapped: "eiscue-noice"),
        // 약어리 — 두드리면 무리를 부른다(원작의 어군 폼). 혼자일 때가 종 기본 그림이다.
        746: Reaction(intact: nil, tapped: "wishiwashi-school"),
        // 메테노 — **방향이 반대다.** 평소엔 유성 껍질이고, 깨지면 안의 코어가 드러난다.
        774: Reaction(intact: "minior-meteor", tapped: nil),
    ]

    /// 이 종은 두드림에 반응하나.
    static func breaks(speciesID: Int?) -> Bool {
        guard let speciesID else { return false }
        return reactions[speciesID] != nil
    }

    /// 지금 그려야 할 슬러그. 반응하지 않는 종이거나 그 상태가 종 기본 그림이면 nil.
    static func slug(speciesID: Int, broken: Bool) -> String? {
        guard let reaction = reactions[speciesID] else { return nil }
        return broken ? reaction.tapped : reaction.intact
    }

    /// 몇 번 두드려야 하나.
    ///
    /// 원작은 **한 대만 맞아도** 깨진다. 여기서 연타를 요구하는 건 고증이 아니라 오작동 방지다 —
    /// 펫을 한 번 누르는 건 팝오버를 여는 기존 조작이라, 그것과 겹치면 안 된다.
    static let tapsToBreak = 3
}
