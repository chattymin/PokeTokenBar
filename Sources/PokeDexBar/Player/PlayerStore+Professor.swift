import Foundation

/// 박사에게 보내기 — 필요 없는 개체를 보내고 포인트를 받는다.
///
/// **이 앱에서 개체가 박스에서 빠지는 유일한 경로다.** 되돌릴 수 없으므로 확인은 화면이 맡고,
/// 여기서는 파트너만 막는다(파트너 시계·폼 상태가 통째로 사라지는 것을 원천 차단).
extension PlayerStore {
    /// 이 개체를 보내면 받을 포인트. **파트너거나 별표면 nil** — 보낼 수 없다는 뜻이고, 화면은
    /// 이 nil 로 버튼을 안 만든다(조건을 화면이 따로 적으면 스토어와 갈린다).
    ///
    /// 이 판정 하나가 단건 보내기·대량 보내기·선택 모드의 셀 판정을 전부 지킨다 — 별표 가드를
    /// 여기 두면 새 경로가 생겨도 자동으로 막힌다.
    func releaseValue(_ individual: Individual) -> Int? {
        guard individual.id != state.partnerID else { return nil }
        guard !individual.starred else { return nil }
        return ReleaseBalance.points(for: individual)
    }

    /// 박사에게 보낸다. 박스에서 빼고 포인트를 더한다. 보낼 수 없으면 nil.
    ///
    /// **`dex` 는 건드리지 않는다** — 도감은 만난 기록이지 소유 기록이 아니다.
    @discardableResult
    func releaseToProfessor(individualID: UUID) -> Int? {
        guard let index = state.box.firstIndex(where: { $0.id == individualID }) else { return nil }
        guard let points = releaseValue(state.box[index]) else { return nil }
        mutate { s in
            // 인덱스를 다시 찾는다 — 위 계산과 이 변형 사이에 배열이 바뀔 일은 없지만,
            // id 로 다시 찾는 것이 이 저장소가 정한 형태다.
            guard let i = s.box.firstIndex(where: { $0.id == individualID }) else { return }
            s.box.remove(at: i)
            s.researchPoints = min(ReleaseBalance.maxPoints, s.researchPoints + points)
        }
        return points
    }

    /// 여러 마리를 한 번에 보낸다. 보낼 수 없는 id(파트너·박스에 없는 개체)는 건너뛰고 나머지를
    /// 보내며, 돌려주는 값은 **실제로 보낸 만큼**의 포인트 합이다.
    ///
    /// **한 번의 `mutate`** 로 끝난다 — 마리마다 `releaseToProfessor` 를 부르면 저장이 스무 번
    /// 일어나고, 중간에 실패하면 절반만 나간 상태가 남는다.
    ///
    /// 파트너를 거르는 것은 화면이 아니라 여기다. 화면이 못 고르게 돼 있어도 마지막 방어선은
    /// 스토어여야 한다 — 파트너가 사라지면 함께한 시계와 폼 상태가 통째로 없어진다.
    @discardableResult
    func releaseManyToProfessor(individualIDs: [UUID]) -> Int {
        // 같은 id 가 두 번 들어와도 한 번만 — 값이 두 배로 잡히면 포인트가 공짜로 는다.
        var seen = Set<UUID>()
        let sendable = individualIDs.filter { seen.insert($0).inserted }
            .compactMap { id -> (UUID, Int)? in
                guard let individual = state.box.first(where: { $0.id == id }),
                      let points = releaseValue(individual) else { return nil }
                return (id, points)
            }
        guard !sendable.isEmpty else { return 0 }
        let total = sendable.reduce(0) { $0 + $1.1 }
        let ids = Set(sendable.map(\.0))
        mutate { s in
            s.box.removeAll { ids.contains($0.id) }
            s.researchPoints = min(ReleaseBalance.maxPoints, s.researchPoints + total)
        }
        return total
    }

    /// 오늘의 제안을 준비한다. 이미 오늘 것이 있거나 인덱스가 아직 없으면 아무것도 하지 않는다.
    ///
    /// 인덱스가 네트워크로 오므로 이 함수는 하루에 여러 번 불릴 수 있다 — 그래도 `ProfessorRoll`
    /// 이 날짜에서 값을 만들기 때문에 같은 3마리가 나온다.
    func refreshProfessorOffers(index: [BaseSpecies]) {
        guard !index.isEmpty, !state.lastDate.isEmpty else { return }
        guard state.professorOfferDate != state.lastDate else { return }
        let date = state.lastDate
        let offers = (0..<ProfessorBalance.offerCount).map { slot in
            ProfessorOffer(individual: Self.offeredIndividual(seed: state.offerSeed, date: date,
                                                              slot: slot,
                                                              index: index, dex: state.dex,
                                                              at: currentDate()))
        }
        mutate {
            $0.professorOfferDate = date
            $0.professorOffers = offers
        }
    }

    /// 제안 한 자리의 개체를 만든다. 알이 깨질 때와 **같은 경로**를 지나므로 이로치·성격·지방·
    /// 태생폼이 그대로 실린다.
    ///
    /// **이로치 부적은 안 본다.** 이건 박사가 가진 아이지 사용자의 운이 아니고, 부적을 하루
    /// 중간에 사면 이미 뜬 제안과 앞뒤가 안 맞는다.
    /// **도감에 없는 종을 밀어 준다**(`EggBalance.unseenBoost`). 제안은 무엇인지 보고 고르는
    /// 자리라, 이미 가진 아이만 셋 뜨면 포인트를 쓸 이유가 없다. 알 뽑기는 이 가중을 안 받는다 —
    /// 무엇이 나올지 모르고 사는 것이 알의 성격이다.
    private static func offeredIndividual(seed: UInt64, date: String, slot: Int,
                                          index: [BaseSpecies], dex: Set<Int>,
                                          at now: Date) -> Individual {
        func roll(_ salt: UInt64) -> Double {
            ProfessorRoll.unit(seed: seed, date: date, slot: slot, salt: salt)
        }
        let grade = EggBalance.rollGrade(roll(ProfessorRoll.Salt.grade))
        let species = EggBalance.pickSpecies(from: index, grade: grade,
                                             roll: roll(ProfessorRoll.Salt.species),
                                             unseenIn: dex)
        let natures = PokemonNature.allCases
        let nature = natures[Int(roll(ProfessorRoll.Salt.nature) * Double(natures.count))
                             % natures.count]
        // 인덱스에 실린 그 종의 성장 타입을 그대로 싣는다 — 못 찾으면(이론상 도달 불가) 기본값.
        let growthRate = index.first(where: { $0.id == species })?.growthRate ?? .mediumFast
        var individual = Individual(
            baseID: species, speciesID: species, pathIDs: [species],
            // 박사의 제안은 부적을 안 받는다(결정적 굴림 — 부적 상태가 끼면 사람마다 같은
            // 날 다른 제안이 되어 되돌릴 수 없는 축이 하나 는다). 기본 분모 64 그대로.
            shiny: EggBalance.rollShiny(roll(ProfessorRoll.Salt.shiny), denominator: 64),
            nature: nature, exp: 0, obtainedAt: now, grade: grade, growthRate: growthRate)
        let region = RegionBalance.rollRegion(speciesID: species,
                                              roll: roll(ProfessorRoll.Salt.region),
                                              pick: roll(ProfessorRoll.Salt.regionPick))
        individual.region = region?.0
        individual.regionVariant = region?.1
        individual.birthForm = BirthFormBalance.rollBirthForm(
            baseID: species, roll: roll(ProfessorRoll.Salt.birthForm),
            pick: roll(ProfessorRoll.Salt.birthFormPick), homeRegion: VivillonRegions.current)
        // 위장은 붙이지 않는다 — 제안은 무엇인지 보여 주고 고르는 자리라, 정체를 숨기면
        // 사용자가 무엇을 사는지 모른 채 값을 치르게 된다.
        return individual
    }

    /// 제안 한 칸을 연다. 이미 열었거나 없는 자리면 nil — 그때는 연출도 다시 안 뜬다.
    ///
    /// **값은 안 든다.** 여는 것은 무엇인지 보는 일이고, 값은 데려갈 때 치른다.
    @discardableResult
    func openProfessorOffer(offerID: UUID) -> Individual? {
        guard let slot = state.professorOffers.firstIndex(where: { $0.id == offerID }),
              !state.professorOffers[slot].opened else { return nil }
        let individual = state.professorOffers[slot].individual
        mutate { $0.professorOffers[slot].opened = true }
        return individual
    }

    /// 제안을 교환한다. 포인트가 모자라거나 이미 데려간 자리면 nil — **이때 차감도 없다.**
    @discardableResult
    func acceptProfessorOffer(offerID: UUID) -> Individual? {
        guard let slot = state.professorOffers.firstIndex(where: { $0.id == offerID }),
              state.professorOffers[slot].opened,          // 안 연 것은 못 데려간다
              !state.professorOffers[slot].claimed else { return nil }
        let offer = state.professorOffers[slot]
        let price = ProfessorBalance.price(grade: offer.individual.grade)
        guard state.researchPoints >= price else { return nil }

        // 보이던 그 개체를 그대로 데려간다. id 와 얻은 시각만 지금 것으로 새로 찍는다 —
        // 제안이 만들어진 시각이 아니라 손에 들어온 시각이 "얻은 날" 이다.
        var taken = offer.individual
        taken.id = UUID()
        taken.obtainedAt = currentDate()
        // **넣기 전에** 재야 한다 — 부화·진화와 같은 이유로, 넣은 뒤에 재면 방금 데려온 아이
        // 때문에 항상 참이 되어 감면이 영영 안 걸린다. 박스에 개체가 들어오는 경로는 전부
        // 이 순서를 지켜야 한다(`chooseStarter`·`claimHatch`·`evolve`·`addForTesting`).
        let hadSpeedup = HatchSpeedup.present(in: state.box)
        mutate {
            $0.researchPoints -= price
            $0.professorOffers[slot].claimed = true
            $0.box.append(taken)
            $0.dexForms.insert(DexKey.key(for: taken))
        }
        applyHatchSpeedupIfNewlyEarned(hadSpeedupBefore: hadSpeedup)
        return taken
    }
}
