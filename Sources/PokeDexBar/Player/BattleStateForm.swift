import Foundation

/// 배틀 중에만 바뀌는 모습을, 배틀이 없는 이 앱의 동작으로 옮긴 것.
///
/// `BrokenForm`(맞으면 깨진다 → 펫을 두드린다)과 같은 계열이다. 트리거를 지어내지 않고
/// **원작의 뜻에 가장 가까운 앱 동작**을 찾아 붙인다는 규칙을 공유한다. 도감은 이 모습들을
/// 세지 않는다 — 상태이지 종이 아니다(`DexKey` 가 메가·깨짐·위장·히어로를 무시하는 것과 같다).
enum BattleStateForm {
    // MARK: 윽우지 — 먹이를 물고 온다

    static let cramorantID = 845

    /// 먹이를 문 두 모습. 원작은 사냥(파도타기·다이빙)에서 돌아올 때 HP 에 따라 갈리는데,
    /// 이 앱엔 HP 도 배틀도 없다. **파트너로 지정할 때마다 굴린다**(사용자 결정) — 곁에 두는
    /// 것이 곧 데리고 나가는 것이라, "나갔다 물고 왔다"가 거기서 자연스럽게 나온다.
    ///
    /// 확률은 기본 50 / 갈망태 35 / 피카침 15. 피카침이 가장 드문 것은 원작을 따른 것이다
    /// (HP 가 절반 아래로 떨어져야 나오는 모습이라 실제로도 덜 보인다).
    static let gulpingPermille = 350
    static let gorgingPermille = 150

    /// 지금 물고 있는 것. **곁에 있을 때만** 문다 — 박스에 있는 동안은 사냥 중이 아니다.
    ///
    /// 굴림은 개체 id 와 **파트너를 몇 번 마쳤나**(`partnerStintsEnded`)에서 유도한다.
    /// 저장 필드를 안 늘리려는 것만이 아니다: 한 번 곁에 둔 동안에는 값이 안 바뀌어야 하고
    /// (매 프레임 다시 굴리면 입에 든 것이 깜빡인다), 내렸다 다시 올리면 새로 굴려야 한다.
    /// 그 둘을 동시에 만족하는 축이 이 카운터다 — 지내는 동안은 고정, 교대하면 증가.
    static func cramorantSlug(individual: Individual) -> String? {
        guard individual.speciesID == cramorantID, individual.partnerSince != nil else { return nil }
        let roll = Int(stintUnit(individual) * 1000)
        if roll < gorgingPermille { return "cramorant-gorging" }
        if roll < gorgingPermille + gulpingPermille { return "cramorant-gulping" }
        return nil   // 빈손 — 기본 모습
    }

    // MARK: 체리꼬 — 꽃이 핀다

    static let cherrimID = 421
    /// 꽃이 필 확률(천분율). 원작의 「플라워기프트」는 쨍쨍햇살에서 피는데 앱엔 날씨가 없어,
    /// **곁에 둘 때마다 굴린다**(윽우지와 같은 축·같은 사용자 결정).
    static let bloomPermille = 200

    /// 지금 피었나. 윽우지와 같은 이유로 곁에 있을 때만 — 박스에서 혼자 피어 있지 않는다.
    static func cherrimSlug(individual: Individual) -> String? {
        guard individual.speciesID == cherrimID, individual.partnerSince != nil else { return nil }
        return Int(stintUnit(individual) * 1000) < bloomPermille ? "cherrim-sunshine" : nil
    }

    /// 0…1. 개체와 그 개체의 파트너 횟수에 묶여 결정적이다.
    ///
    /// 윽우지와 체리꼬가 **같은 값을 쓴다** — 한 개체는 한 종이라 둘이 동시에 걸리는 일이 없어
    /// 상관관계가 생길 수 없다. 굴림을 따로 두면 축만 늘고 얻는 게 없다.
    static func stintUnit(_ individual: Individual) -> Double {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325   // FNV-1a 64
        func mix(_ byte: UInt8) {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        withUnsafeBytes(of: individual.id.uuid) { $0.forEach(mix) }
        withUnsafeBytes(of: UInt64(bitPattern: Int64(individual.partnerStintsEnded))) { $0.forEach(mix) }
        return Double(hash % 1_000_000) / 1_000_000
    }

    // MARK: 토큰 흐름을 보는 폼 — 모르페코와 킬가르도

    static let morpekoID = 877
    static let aegislashID = 681

    /// 이 종은 토큰 흐름에 반응하나. 반응하는 종만 `recentlyActive` 를 갱신한다.
    static func followsTokenFlow(speciesID: Int) -> Bool {
        speciesID == morpekoID || speciesID == aegislashID
    }

    /// 이만큼 토큰이 안 들어오면 "쉬는 중" 으로 본다.
    ///
    /// 원작은 **매 턴** 뒤집히는데 이 앱엔 턴이 없다. 대신 "먹는 것"에 해당하는 흐름이 하나
    /// 있다 — 토큰이다(플로팅 펫이 이미 그 속도로 빨라진다). 그래서 쓰고 있으면 배부름,
    /// 한동안 안 쓰면 배고픔이 된다. 30분은 갱신 주기(기본 2분)보다 충분히 길어 깜빡이지 않고,
    /// "자리를 떴다"고 부를 만한 최소 단위다.
    static let idleAfter: TimeInterval = 30 * 60

    /// 마지막으로 토큰이 들어온 시각으로 **지금 일하는 중인가**를 판정한다.
    ///
    /// `nil` 을 돌려주는 것이 중요하다 — 기록이 아예 없으면(새 세이브) "쉬는 중"도 "일하는 중"도
    /// 아니다. 두 종이 이 신호를 **반대 방향으로** 쓰기 때문이다: 모르페코는 쉬면 배고픈 모습이고
    /// 킬가르도는 일하면 블레이드다. 불리언 하나로 접으면 한쪽은 켜자마자 특수 모습이 되어,
    /// 그게 기본값처럼 보인다.
    static func activity(lastTokenAt: Date?, now: Date) -> Bool? {
        guard let lastTokenAt else { return nil }
        return now.timeIntervalSince(lastTokenAt) < idleAfter
    }

    /// 모르페코의 배고픔 — **쉬는 중일 때만.** 기록이 없으면 배부른 쪽(기본 모습).
    static func morpekoSlug(individual: Individual) -> String? {
        guard individual.speciesID == morpekoID, individual.recentlyActive == false else { return nil }
        return "morpeko-hangry"
    }

    /// 킬가르도의 블레이드 — **일하는 중일 때만.** 원작의 「배틀스위치」가 *공격할 때* 칼로
    /// 바뀌는 그대로다(방패가 기본). 기록이 없으면 방패.
    static func aegislashSlug(individual: Individual) -> String? {
        guard individual.speciesID == aegislashID, individual.recentlyActive == true else { return nil }
        return "aegislash-blade"
    }
}
