import Foundation

/// 박사에게 보내기 — 필요 없는 개체를 보내고 포인트를 받는다.
///
/// **이 앱에서 개체가 박스에서 빠지는 유일한 경로다.** 되돌릴 수 없으므로 확인은 화면이 맡고,
/// 여기서는 파트너만 막는다(파트너 시계·폼 상태가 통째로 사라지는 것을 원천 차단).
extension PlayerStore {
    /// 이 개체를 보내면 받을 포인트. **파트너면 nil** — 보낼 수 없다는 뜻이고, 화면은 이 nil 로
    /// 버튼을 안 만든다(조건을 화면이 따로 적으면 스토어와 갈린다).
    func releaseValue(_ individual: Individual) -> Int? {
        guard individual.id != state.partnerID else { return nil }
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

    /// 오늘의 제안을 준비한다. 이미 오늘 것이 있거나 인덱스가 아직 없으면 아무것도 하지 않는다.
    ///
    /// 인덱스가 네트워크로 오므로 이 함수는 하루에 여러 번 불릴 수 있다 — 그래도 `ProfessorRoll`
    /// 이 날짜에서 값을 만들기 때문에 같은 3마리가 나온다.
    func refreshProfessorOffers(index: [BaseSpecies]) {
        guard !index.isEmpty, !state.lastDate.isEmpty else { return }
        guard state.professorOfferDate != state.lastDate else { return }
        let date = state.lastDate
        let offers = (0..<ProfessorBalance.offerCount).map { slot in
            ProfessorOffer(individual: Self.offeredIndividual(date: date, slot: slot,
                                                              index: index, at: currentDate()))
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
    private static func offeredIndividual(date: String, slot: Int,
                                          index: [BaseSpecies], at now: Date) -> Individual {
        func roll(_ salt: UInt64) -> Double { ProfessorRoll.unit(date: date, slot: slot, salt: salt) }
        let grade = EggBalance.rollGrade(roll(ProfessorRoll.Salt.grade))
        let species = EggBalance.pickSpecies(from: index, grade: grade,
                                             roll: roll(ProfessorRoll.Salt.species))
        let natures = PokemonNature.allCases
        let nature = natures[Int(roll(ProfessorRoll.Salt.nature) * Double(natures.count))
                             % natures.count]
        var individual = Individual(
            baseID: species, speciesID: species, pathIDs: [species],
            shiny: EggBalance.rollShiny(roll(ProfessorRoll.Salt.shiny), hasCharm: false),
            nature: nature, exp: 0, obtainedAt: now, grade: grade)
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

    /// 제안을 교환한다. 포인트가 모자라거나 이미 데려간 자리면 nil — **이때 차감도 없다.**
    @discardableResult
    func acceptProfessorOffer(offerID: UUID) -> Individual? {
        guard let slot = state.professorOffers.firstIndex(where: { $0.id == offerID }),
              !state.professorOffers[slot].claimed else { return nil }
        let offer = state.professorOffers[slot]
        let price = ProfessorBalance.price(grade: offer.individual.grade)
        guard state.researchPoints >= price else { return nil }

        // 보이던 그 개체를 그대로 데려간다. id 와 얻은 시각만 지금 것으로 새로 찍는다 —
        // 제안이 만들어진 시각이 아니라 손에 들어온 시각이 "얻은 날" 이다.
        var taken = offer.individual
        taken.id = UUID()
        taken.obtainedAt = currentDate()
        mutate {
            $0.researchPoints -= price
            $0.professorOffers[slot].claimed = true
            $0.box.append(taken)
            $0.dex.insert(taken.speciesID)
        }
        return taken
    }
}
