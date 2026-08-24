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
    case expCandy(Int)
    case shinyCandy(Int)
    /// 무지개 부적 — 이로치 부적의 업그레이드(1/64 → 1/32). 전국도감 완성에서만 나오고,
    /// 이로치 부적이 없어도 받는다.
    case rainbowCharm
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
    /// 마릿수 보상은 상점 시세와 재 본 것이다: 반짝사탕은 상점에서 30억이라 큰 고비에만 두고,
    /// 알은 뽑기(1천만)보다 "등급이 보장된다"는 점이 값이다. 전부 **일회성**이라 후해도 경제가
    /// 안 밀린다.
    static let all: [DexMission] = {
        let ladder: [(Int, [DexMissionReward])] = [
            (10, [.expCandy(3)]),
            (25, [.eggTicket(.rare)]),
            (50, [.expCandy(10)]),
            (100, [.eggTicket(.epic)]),
            (150, [.shinyCandy(1)]),
            (250, [.eggTicket(.epic)]),
            (400, [.shinyCandy(2)]),
            (600, [.eggTicket(.legendary)]),
            (800, [.shinyCandy(3)]),
            (1000, [.eggTicket(.legendary)]),
        ]
        var missions = ladder.map { count, rewards in
            DexMission(id: "species-\(count)", kind: .species(count), rewards: rewards)
        }
        // 세대 완성 — 그 세대의 레전더리까지 전부라 난도가 높다. 보상도 그만큼.
        for generation in generations.keys.sorted() {
            missions.append(DexMission(id: "gen-\(generation)", kind: .generation(generation),
                                       rewards: [.eggTicket(.legendary), .shinyCandy(1)]))
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
