import Foundation

/// 리전 변이의 확률과 진화 규칙.
enum RegionBalance {
    /// 지방 모습이 있는 종이 부화할 때, 원종이 아니라 지방 모습으로 나올 확률(1000분율).
    /// 원종이 기본이어야 한다 — 지방 모습이 더 흔해지면 관동 나옹이 오히려 희귀해진다.
    static let regionalPermille = 200

    /// 부화 굴림 결과. `nil` 이면 원종.
    /// 굴림 두 번(지방이 될까 → 어느 지방일까)을 한 함수로 묶어 순수하게 테스트한다.
    static func rollRegion(speciesID: Int, roll: Double, pick: Double) -> (Region, String?)? {
        let candidates = RegionalFormCatalog.forms(speciesID: speciesID)
        guard !candidates.isEmpty else { return nil }
        guard Int(roll * 1000) < regionalPermille else { return nil }
        // 후보는 (지방, 변형) 단위다 — 팔데아 켄타로스는 셋이라 하나를 더 골라야 한다.
        let index = min(candidates.count - 1, max(0, Int(pick * Double(candidates.count))))
        let chosen = candidates[index]
        return (chosen.region, chosen.variant)
    }

    /// 지방이 진화 후보를 갈라놓는 종만 적는다. 여기 없는 종은 지방과 무관하게 원래 후보를 다 쓰고,
    /// 지방은 그대로 이어진다(알로라 식스테일 → 알로라 나인테일 — 종 번호가 같아 표가 필요 없다).
    ///
    /// 값은 "이 지방이면 이 종으로만 진화한다". 원종은 `nil` 키로 적는다.
    /// PokéAPI 진화 체인은 두 갈래를 한꺼번에 돌려주므로(`meowth → persian | perrserker`)
    /// 이 표가 없으면 관동 나옹도 나이킹이 될 수 있다.
    static let branchesByRegion: [Int: [Region?: [Int]]] = [
        52: [nil: [53], .alola: [53], .galar: [863]],        // 나옹 → 페르시온 / 나이킹
        194: [nil: [195], .paldea: [980]],                    // 우파 → 늪지꼬 / 토오
        215: [nil: [461], .hisui: [903]],                     // 포챠나 → 포푸니라 / 다크메이지
        211: [nil: [], .hisui: [904]],                        // 침바루 → (없음) / 대쓰여너
        562: [nil: [563], .galar: [867]],                     // 데스마스 → 데스니칸 / 데스판
        264: [nil: [], .galar: [862]],                        // 직구리 → (없음) / 가로막구리
        83: [nil: [], .galar: [865]],                         // 파오리 → (없음) / 창파나이트
        222: [nil: [], .galar: [864]],                        // 코산호 → (없음) / 산호르곤
        122: [nil: [], .galar: [866]],                        // 마임맨 → (없음) / 마임꽁꽁
    ]

    /// 이 개체가 갈 수 있는 진화 후보로 좁힌다. 표에 없는 종이면 원래 후보 그대로.
    static func allowedChoices(_ choices: [Int], speciesID: Int, region: Region?) -> [Int] {
        guard let table = branchesByRegion[speciesID] else { return choices }
        // 표에 그 지방 항목이 없으면(예: 알로라 나옹은 원종과 같은 갈래) 원종 규칙을 따른다.
        let allowed = table[region] ?? table[nil] ?? []
        return choices.filter { allowed.contains($0) }
    }
}
