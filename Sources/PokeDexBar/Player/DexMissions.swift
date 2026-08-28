import Foundation

/// 도감 미션 — 채운 종 수와 세대 완성에 보상을 건다.
///
/// **본가의 구조를 그대로 옮겼다**: 일정 마릿수마다 박사가 주는 보상(SV 의 조수 보상),
/// 지방도감(여기서는 세대) 완성 보상, 그리고 전국도감 완성의 부적(본가는 빛나는부적을 준다 —
/// 이 앱은 그걸 상점에서 팔고 있으므로, 완성 보상은 그 **업그레이드**다).
///
/// **보상은 알과 아이템뿐이다.** 토큰은 이 앱에서 오직 실제 AI 사용량에서만 나온다 — 그 약속을
/// 미션이 깨면 재화의 뜻 자체가 흐려진다. 알 보상은 도감을 다시 채우는 순환이 된다.
enum DexMissionReward: Equatable, Sendable {
    /// 그 등급이 **확정**인 알 뽑기 확정권. 알을 그 자리에서 주지 않는 이유: 알은 홈 탭의
    /// 부화 슬롯에 놓여서, 도감 탭에서 받으면 "받아졌는지" 가 안 보이고 빈 슬롯 요구까지
    /// 딸려 온다(사용자 지적 — "자꾸 까먹을 것 같다"). 확정권은 가방에 담겼다가 **상점의
    /// 알 뽑기 자리에서** 쓰인다 — 개봉의 순간이 원래 알이 태어나는 자리로 돌아간다.
    case eggTicket(Grade)
    /// 상점 소모품 n 개 — 사탕, 그리고 세대 완성의 대표 아이템(메가스톤·다이버섯).
    case item(ShopItem, Int)
    /// 무지개 부적 — 이로치 부적의 업그레이드(1/64 → 1/32). 전국도감 완성에서만 나오고,
    /// 이로치 부적이 없어도 받는다.
    case rainbowCharm
    /// 포켓몬 개체를 직접 지급 — 받는 즉시 박스와 도감에 들어간다. 알에서 안 나오는 종
    /// (`EggBalance.rewardOnlySpecies`)의 유일한 입수처다 — 레지 패밀리를 다 모으면
    /// 레지기가스가 깨어나는 본가 전승 그대로. 등급·곡선을 값으로 들고 다니는 이유:
    /// 지급 자리(`PlayerStore.grant`)에는 네트워크 인덱스가 없다.
    case pokemon(speciesID: Int, grade: Grade, growthRate: GrowthRate, gender: Gender)
}

extension DexMissionReward {
    /// 지급 종의 표시 이름. 종 이름은 원래 네트워크(진화 라인)에서 오지만, 보상 줄은 인덱스가
    /// 아직 없어도 그려져야 해서 지급되는 종만 여기 상수로 둔다 — 지급 종을 더하면 여기도 더한다.
    static func speciesName(_ id: Int, _ lang: AppLanguage) -> String {
        let names: (String, String, String)
        switch id {
        case 486: names = ("레지기가스", "Regigigas", "レジギガス")
        default: names = ("#\(id)", "#\(id)", "#\(id)")
        }
        switch lang { case .ko: return names.0; case .en: return names.1; case .ja: return names.2 }
    }
}

struct DexMission: Equatable, Sendable, Identifiable {
    enum Kind: Equatable, Sendable {
        /// 채운 종 수가 이만큼.
        case species(Int)
        /// 이 세대의 전 종.
        case generation(Int)
        /// 1025종 전부.
        case completion
    }
    let id: String
    let kind: Kind
    let rewards: [DexMissionReward]
}

enum DexMissions {
    /// 세대 경계 — 본가 전국도감 그대로.
    static let generations: [Int: ClosedRange<Int>] = [
        1: 1...151, 2: 152...251, 3: 252...386, 4: 387...493, 5: 494...649,
        6: 650...721, 7: 722...809, 8: 810...905, 9: 906...1025,
    ]

    /// 전체 미션. 순서가 곧 화면 순서다 — 마릿수 사다리, 세대, 완성.
    ///
    /// 마릿수 보상은 상점 시세와 재 본 것이다: 알 확정권은 뽑기(1천만)보다 "등급이 보장된다"
    /// 는 점이 값이고, 전부 일회성이라 후해도 경제가 안 밀린다.
    ///
    /// **반짝사탕은 전체를 통틀어 2개다**(400종·800종). 처음엔 사다리에 6개 + 세대 완성마다
    /// 1개씩 15개였는데, 상점가 3B 짜리가 45B 어치 쏟아지는 셈이라 걷어냈다(사용자 지적 —
    /// "너무 많이 주는 것 같아"). 이로치는 이 앱에서 가장 귀한 것이라, 확정 지급은 큰 고비
    /// 두 곳이면 족하다 — 세대 완성은 레전더리 확정권만으로 이미 크다. 테스트가 총량을 잠근다.
    static let all: [DexMission] = {
        let ladder: [(Int, [DexMissionReward])] = [
            (10, [.item(.expCandy, 3)]),
            (25, [.eggTicket(.rare)]),
            (50, [.item(.expCandy, 10)]),
            (100, [.eggTicket(.legendary)]),
            (150, [.item(.expCandy, 20)]),
            (250, [.eggTicket(.legendary)]),
            (400, [.item(.shinyCandy, 1)]),
            (600, [.eggTicket(.legendary)]),
            (800, [.item(.shinyCandy, 1)]),
            (1000, [.eggTicket(.legendary)]),
        ]
        var missions = ladder.map { count, rewards in
            DexMission(id: "species-\(count)", kind: .species(count), rewards: rewards)
        }
        // 세대 완성 — 그 세대의 레전더리까지 전부라 난도가 높다(달성 비용 수십 B 규모).
        // 레전더리 확정권 하나(~500M)로는 약해서, **세대마다 대표 아이템을 하나씩 얹는다**
        // (사용자 배정): 메가스톤은 메가진화의 세대들(6=XY · 3=ORAS 리메이크 · 7=SM 계승),
        // 다이버섯은 다이맥스의 8세대와 거다이맥스가 몰린 관동(1). 남는 2·4·5·9 는 반짝사탕 —
        // 이 넷이 반짝사탕 총량을 2 → 6 으로 되돌리는데, "너무 많다" 로 걷어낸 15 와 달리
        // 사용자가 직접 고른 수준이다(가드가 6 을 잠근다).
        for generation in generations.keys.sorted() {
            let signature: DexMissionReward = switch generation {
            case 3, 6, 7: .item(.megaStone, 1)
            case 1, 8: .item(.dynamaxMushroom, 1)
            default: .item(.shinyCandy, 1)
            }
            missions.append(DexMission(id: "gen-\(generation)", kind: .generation(generation),
                                       rewards: [.eggTicket(.legendary), signature]))
        }
        missions.append(DexMission(id: "completion", kind: .completion,
                                   rewards: [.rainbowCharm]))
        return missions
    }()

    /// 이 미션의 (지금까지, 목표). 진행 표시와 달성 판정이 같은 값을 읽는다.
    static func progress(of mission: DexMission, dex: Set<Int>) -> (done: Int, target: Int) {
        switch mission.kind {
        case .species(let count):
            return (min(dex.count, count), count)
        case .generation(let generation):
            guard let range = generations[generation] else { return (0, 1) }
            return (dex.count(where: { range.contains($0) }), range.count)
        case .completion:
            return (min(dex.count, 1025), 1025)
        }
    }

    static func achieved(_ mission: DexMission, dex: Set<Int>) -> Bool {
        let p = progress(of: mission, dex: dex)
        return p.done >= p.target
    }
}
