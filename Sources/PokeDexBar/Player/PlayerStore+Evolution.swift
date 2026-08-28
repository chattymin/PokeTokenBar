import Foundation

/// 진화 — 조건 판정과 실행. **자동으로 일어나지 않는다.** 조건을 채우면 UI 가 배지를 띄우고,
/// 사용자가 누를 때 `evolve` 가 불린다(미루기·분기 선택이 가능해야 하기 때문).
extension PlayerStore {
    /// **라인이 도착하면 그 라인이 아는 모든 종의 성장 곡선으로 박스를 바로잡는다.**
    ///
    /// `growthRate` 를 갱신하는 자리가 예전엔 `evolve` 하나뿐이었다 — 마이그레이션으로 들어온
    /// 개체와 스타터는 전부 `.mediumFast` 로 태어나는데(네트워크 없이 만들어지는 자리라 실제
    /// 곡선을 모른다), 그 뒤로 진화하지 않으면(이미 최종형이거나 아직 안 컸으면) 영영
    /// 안 바로잡힌다. 그러면 실제로는 `slow`인 레거시 전설이 `mediumFast` 곡선으로 레벨이
    /// 계산되고, 그 레벨이 그대로 `ReleaseBalance.points` 로 새 나간다.
    ///
    /// 호출부(`PopoverView.loadLine`)는 라인을 fetch 할 때마다 이 함수를 부른다 — **멱등**이라
    /// (이미 맞는 값이면 손대지 않는다) 몇 번을 다시 불러도 값싸다. 그 라인이 모르는 종(다른
    /// 라인 소속)은 그대로 둔다.
    func backfillGrowthRates(from line: EvoLine) {
        // 먼저 읽기만 해서 바뀔 게 있는지 본다 — `state` 는 밖에서 못 쓰므로(private(set))
        // 실제 대입은 `mutate` 안에서 하는데, 바뀐 게 없어도 `mutate` 를 부르면 매번 저장이
        // 돈다(멱등이 아니게 된다). 그래서 쓰기 전에 먼저 없는지를 판정한다.
        let indicesToFix = state.box.indices.filter { index in
            guard let rate = line.growthRate(of: state.box[index].speciesID) else { return false }
            return state.box[index].growthRate != rate
        }
        guard !indicesToFix.isEmpty else { return }
        mutate { s in
            for index in indicesToFix {
                if let rate = line.growthRate(of: s.box[index].speciesID) { s.box[index].growthRate = rate }
            }
        }
    }

    /// 성별이 없던 시절의 개체에 성별을 채운다 — `backfillGrowthRates` 와 같은 자리·같은 규율
    /// (멱등, 라인이 모르는 종은 그대로).
    ///
    /// **이미 성별이 있으면 절대 다시 굴리지 않는다.** 다시 굴리면 앱을 켤 때마다 성별이 바뀌고,
    /// 성별로 갈리는 진화가 그때그때 달라진다. 그래서 `nil` 인 것만 채운다 — 무성별은 `nil` 이
    /// 아니라 `.genderless` 로 적히므로 여기 다시 걸리지 않는다.
    ///
    /// 굴림은 개체 id 에서 유도한다. 난수기를 쓰면 같은 개체가 기기마다 다른 성별이 되고,
    /// 저장 실패 시 다음 기동에 또 달라진다 — id 는 그 개체에 붙어 있어 언제 어디서 굴려도 같다.
    func backfillGenders(from line: EvoLine) {
        // 라인은 **지금 종**의 성비를 안다 — 진화형이 성별 고정인 경우(비퀸은 암컷만)
        // 그쪽이 더 정확하다. 다만 라인 하나는 한 계보만 알아서 박스 전체를 못 덮는다.
        backfillGenders { line.genderRate(of: $0.speciesID) }
    }

    /// **박스 전체를 한 번에 채우는 경로.** 라인 기반 보정은 그때 열린 계보만 훑어서, 박스에
    /// 서른 종이 있으면 서른 계보를 다 열어야 채워졌다 — 사실상 "다 적용"이 안 됐다(사용자 지적).
    /// 종 인덱스는 base 종 전부를 들고 있으므로 `baseID` 로 찾으면 진화한 개체까지 한 번에 덮는다.
    ///
    /// `baseID` 로 찾는 게 맞는 이유: 성별은 **부화 시점에 base 종의 성비로** 정해지는 값이라,
    /// 그때 굴렸을 값을 그대로 복원하는 것이다.
    func backfillGenders(from index: [BaseSpecies]) {
        guard !index.isEmpty else { return }
        var rates: [Int: Int] = [:]
        for entry in index { rates[entry.id] = entry.genderRate }
        backfillGenders { individual in
            // 메타몽은 인덱스에서 빠져 있다(일반 부화 풀 제외) — 무성별이라 여기서 채운다.
            // 안 채우면 위장이 풀린 메타몽만 영영 성별이 안 정해진 채로 남는다.
            if individual.speciesID == DittoDisguise.speciesID { return GenderBalance.genderless }
            // `baseID` 가 먼저다 — 성별은 부화 시점에 base 종의 성비로 정해지므로 그 값이 맞다.
            // 지금 종으로 물러나는 이유: 옛 세이브에는 `baseID` 가 base 종이 아닌 개체가 있다
            // (실측: 피카츄가 `baseID: 25` 로 적힌 개체 — 피카츄는 피츄에서 진화하므로 인덱스에
            // 없다). 둘 다 없으면 nil 로 두고, 그 개체를 열 때 라인 기반 보정이 받는다.
            return rates[individual.baseID] ?? rates[individual.speciesID]
        }
    }

    /// 성별이 없던 시절의 개체에 성별을 채운다 — `backfillGrowthRates` 와 같은 규율
    /// (멱등, 성비를 모르는 종은 그대로).
    ///
    /// **이미 성별이 있으면 절대 다시 굴리지 않는다.** 다시 굴리면 앱을 켤 때마다 성별이 바뀌고,
    /// 성별로 갈리는 진화가 그때그때 달라진다. 그래서 `nil` 인 것만 채운다 — 무성별은 `nil` 이
    /// 아니라 `.genderless` 로 적히므로 여기 다시 걸리지 않는다.
    ///
    /// 굴림은 개체 id 에서 유도한다. 난수기를 쓰면 같은 개체가 기기마다 다른 성별이 되고,
    /// 저장 실패 시 다음 기동에 또 달라진다 — id 는 그 개체에 붙어 있어 언제 어디서 굴려도 같다.
    func backfillGenders(resolve: (Individual) -> Int?) {
        // 먼저 읽기만 해서 바뀔 게 있는지 본다 — 없는데 `mutate` 를 부르면 매번 저장이 돈다.
        let targets = state.box.indices.filter {
            state.box[$0].gender == nil && resolve(state.box[$0]) != nil
        }
        guard !targets.isEmpty else { return }
        mutate { s in
            for index in targets {
                guard let rate = resolve(s.box[index]) else { continue }
                // **종을 넘긴다** — 성별 고정 종(엘레이드·염뉴트 등)은 base 성비로 굴리면
                // 존재할 수 없는 조합이 나온다. 굴림 앞에 잠금 표가 선다.
                s.box[index].gender = GenderBalance.roll(
                    species: s.box[index].speciesID, rate: rate,
                    roll: Self.stableUnit(from: s.box[index].id))
            }
        }
    }

    /// 개체 id → 0…1. 결정적이라 몇 번을 다시 불러도 같은 값이다.
    nonisolated static func stableUnit(from id: UUID) -> Double {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325   // FNV-1a 64
        withUnsafeBytes(of: id.uuid) { bytes in
            for byte in bytes {
                hash ^= UInt64(byte)
                hash = hash &* 0x0000_0100_0000_01B3
            }
        }
        return Double(hash % 1_000_000) / 1_000_000
    }

    /// 지금 형태에서 갈 수 있는 다음 종들. 최종형이면 빈 배열.
    func evolutionChoices(_ individual: Individual, line: EvoLine) -> [Int] {
        guard let node = line.tree.node(withID: individual.speciesID) else { return [] }
        // PokéAPI 체인은 지방 갈래를 한꺼번에 돌려준다(`meowth → persian | perrserker`) —
        // 개체의 지방으로 좁히지 않으면 관동 나옹도 나이킹이 된다.
        let byRegion = RegionBalance.allowedChoices(node.children.map(\.speciesID),
                                                    speciesID: individual.speciesID,
                                                    region: individual.region)
        // **성별 갈래를 걸러낸다** — 여섯 종뿐이지만(도롱마담·나메일·비퀸·엘레이드·눈여아·염뉴트)
        // 안 거르면 수컷 눈꼬마가 눈여아가 된다. 지방 게이트 바로 뒤에 두는 이유: 둘 다 "이 개체가
        // 갈 수 있는 갈래인가" 를 정하는 같은 종류의 판정이고, 도구·레벨 조건보다 앞선다.
        //
        // **성별을 아직 모르는 개체(옛 세이브)는 제한 있는 갈래를 막는다.** 열어 두면 수컷일 수도
        // 있는 아이가 암컷 전용으로 진화해 되돌릴 수 없다 — 보정(`backfillGenders`)이 라인과 같은
        // 자리에서 돌므로 이 화면이 열릴 즈음엔 이미 채워져 있다.
        return byRegion.filter { child in
            guard let required = node.children.first(where: { $0.speciesID == child })?.requiredGender
            else { return true }
            return individual.gender == required
        }
    }

    /// 이 갈래를 지나려면 무엇이 필요한가. 트리에 없는 종이면 조건 없음으로 본다.
    func requirement(for speciesID: Int, line: EvoLine) -> EvoRequirement {
        line.tree.node(withID: speciesID)?.requirement ?? .none
    }

    /// 그 조건을 지금 만족하는가. 도구는 **갖고 있으면** 되고(쓰는 건 진화 실행 때),
    /// 친밀도·걸음은 그 개체와 함께한 시간으로, 레벨은 성장 곡선으로, 소유는 박스로 판단한다.
    func meetsRequirement(_ requirement: EvoRequirement, for individual: Individual) -> Bool {
        switch requirement {
        case .none: true
        case .item(let item): count(of: item) > 0
        case .friendship:
            individual.partnerDuration(at: currentDate()) >= EvoRequirement.friendshipSeconds
        case .level(let n): individual.level >= n
        case .owns(let speciesID): state.box.contains { $0.speciesID == speciesID }
        case .walked:
            individual.partnerDuration(at: currentDate()) >= EvoRequirement.walkSeconds
        }
    }

    /// 이 종으로 갈 수 있고, 그 조건을 만족하는가. **경험치 임계는 더 이상 없다** —
    /// 조건 자체가 게이트다(레벨 진화면 레벨이, 도구 진화면 도구가).
    func canEvolve(_ individual: Individual, to speciesID: Int, line: EvoLine) -> Bool {
        evolutionChoices(individual, line: line).contains(speciesID)
            && meetsRequirement(requirement(for: speciesID, line: line), for: individual)
    }

    /// "진화 가능" 배지 판정 — 박스 칸(`BoxTabView.readyToEvolve`)과 홈(`PopoverView.
    /// showsEvolutionBadge`)이 함께 쓰는 **단일 소스**. 갈 수 있는 갈래 중 **하나라도** 지금
    /// 조건을 채웠으면 참이다.
    ///
    /// **첫 갈래만 보면 안 된다.** 이브이처럼 첫 갈래(예: 샤미드, 도구 필요)가 막혀 있어도
    /// 다른 갈래(예: 쥬피썬더, 레벨만 필요)가 열려 있을 수 있다 — `.first` 로 줄이면 그 경우
    /// 배지가 다시 죽는다. 두 화면이 이 함수 하나만 쓰게 해서, 한쪽만 고치다 갈리는 것도 막는다.
    func isReadyToEvolve(_ individual: Individual, line: EvoLine) -> Bool {
        evolutionChoices(individual, line: line).contains { canEvolve(individual, to: $0, line: line) }
    }

    /// 진화 실행. 갈 수 없는 종이거나 조건을 못 채웠으면 아무것도 하지 않고 false —
    /// 도구도 소모하지 않는다.
    @discardableResult
    func evolve(individualID: UUID, to speciesID: Int, line: EvoLine) -> Bool {
        guard let index = state.box.firstIndex(where: { $0.id == individualID }) else { return false }
        let individual = state.box[index]
        guard canEvolve(individual, to: speciesID, line: line) else { return false }
        let hadSpeedup = HatchSpeedup.present(in: state.box)
        mutate { state in
            state.box[index].speciesID = speciesID
            state.box[index].pathIDs.append(speciesID)
            // **경험치는 그대로 둔다.** 본가에서 진화는 레벨을 되돌리지 않는다.
            // 알 진행분(`eggProgress`)도 마찬가지다 — 두 계량기 모두 진화와 무관하다.
            // 폼은 종에 달린 것이라 진화하면 풀린다 — 피카츄의 거다이맥스를 라이츄가 이어받을 수 없다.
            state.box[index].form = nil
            // 성장 타입은 종에 달린 것이라 진화하면 새 종의 것으로 갱신한다.
            if let rate = line.growthRate(of: speciesID) { state.box[index].growthRate = rate }
            // 진화가 끝난 개체로 키를 계산한다 — 지방 혈통이면 새 종의 지방 폼으로 등록된다
            // (알로라 식스테일 → 알로라 나인테일즈).
            state.dexForms.insert(DexKey.key(for: state.box[index]))
            // 도구는 소모하지 않는다 — 다시 얻는 값이 며칠의 파트너 시간이라, 없어지면 같은
            // 도구를 두 번째 개체에 쓸 방법이 사실상 없다. 한 번 물어 오면 영구 해금이다.

            // 토중몬(#290) → 아이스크(#291) 진화에 껍질몬(#292)이 딸려 나온다. 본가에서 빈
            // 몬스터볼에 껍질몬이 남는 것을 옮긴 것 — 요구 조건이 아니라 **부수 효과**라 여기 있다.
            if Self.shedinjaParent == individual.speciesID, speciesID == Self.shedinjaSibling {
                var shed = state.box[index]
                shed.id = UUID()
                shed.speciesID = Self.shedinjaID
                shed.pathIDs = individual.pathIDs + [Self.shedinjaID]
                shed.eggProgress = 0
                // **파트너로 지낸 기록은 물려주지 않는다.** `state.box[index]` 를 통째로 복사하면
                // 이싱카와 함께한 시간·리본·사탕 진행분까지 따라와, 방금 생긴 껍질몬이 실제로
                // 함께한 적 없는 시간을 이미 채운 채 등장한다 — eggProgress 와 같은 부류의
                // "공짜 출발" 이다. 껍질몬은 지금 막 생긴 개체이므로 그 기록은 0에서 시작한다.
                shed.partnerSeconds = 0
                shed.partnerSince = nil
                shed.partnerTokens = 0
                shed.candyProgress = 0
                shed.partnerStintsEnded = 0
                shed.obtainedAt = currentDate()
                state.box.append(shed)
                state.dexForms.insert(DexKey.key(for: shed))
            }
        }
        // 진화로 종이 바뀌면서 알을 빨리 깨우는 아이가 될 수 있다 — 부화와 같은 처리를 받는다.
        // 껍질몬이 늘어난 뒤(위 `mutate` 가 끝난 뒤) 판정해야, 껍질몬이 바로 그 조건을 채우는
        // 경우도 놓치지 않는다.
        applyHatchSpeedupIfNewlyEarned(hadSpeedupBefore: hadSpeedup)
        return true
    }

    /// 토중몬(#290) → 아이스크(#291) 진화에 껍질몬(#292)이 딸려 나온다.
    static let shedinjaParent = 290
    static let shedinjaSibling = 291
    static let shedinjaID = 292
}
