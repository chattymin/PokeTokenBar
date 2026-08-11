import XCTest
@testable import PokeDexBar

/// 박사에게 보내기 · 박사의 제안.
@MainActor
final class ProfessorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore(seed: UInt64 = 1) -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("prof-\(UUID().uuidString).json")
        return PlayerStore(fileURL: url, rng: SeededRNG(seed: seed), now: { self.now })
    }

    private func make(_ grade: Grade, path: [Int], exp: Int = 0) -> Individual {
        Individual(baseID: path.first ?? 1, speciesID: path.last ?? 1, pathIDs: path,
                   nature: .hardy, exp: exp, obtainedAt: now, grade: grade)
    }

    // MARK: 보내면 받는 값

    /// 등급기본 — 스펙의 표 그대로.
    func testReleaseBaseValues() {
        XCTAssertEqual(ReleaseBalance.base(grade: .common), 2)
        XCTAssertEqual(ReleaseBalance.base(grade: .rare), 5)
        XCTAssertEqual(ReleaseBalance.base(grade: .epic), 12)
        XCTAssertEqual(ReleaseBalance.base(grade: .legendary), 40)
    }

    /// 경험치 0 기준 표. 진화한 만큼 값이 붙는다.
    func testReleasePointsByStage() {
        for (grade, expected) in [(Grade.common, [2, 4, 6]), (.rare, [5, 10, 15]),
                                  (.epic, [12, 24, 36]), (.legendary, [40, 80, 120])] {
            for (stage, want) in expected.enumerated() {
                let path = Array(1...(stage + 1))
                XCTAssertEqual(ReleaseBalance.points(for: make(grade, path: path)), want,
                               "\(grade) \(stage)단계")
            }
        }
    }

    /// **지금 단계에서 채운 경험치가 더해진다** — 키운 아이일수록 값이 나가야 정리 대상이
    /// 자연히 "안 키운 중복" 이 된다.
    func testReleasePointsIncludeBankedExperience() {
        let threshold = ExpBalance.threshold(grade: .epic, stageIndex: 0)
        let half = make(.epic, path: [4], exp: threshold / 2)
        XCTAssertEqual(ReleaseBalance.points(for: half), 18)   // floor(12 × (0 + 1 + 0.5))
    }

    /// 경험치 비율은 1 에서 멈춘다 — 알 임계까지 쌓인 최종형이 배수로 튀면 안 된다.
    func testReleasePointsClampTheExperienceRatio() {
        let huge = make(.epic, path: [4, 5, 6], exp: Int.max / 4)
        XCTAssertEqual(ReleaseBalance.points(for: huge), 48)   // floor(12 × (2 + 1 + 1))
    }

    // MARK: 포인트 저장

    /// **앱을 껐다 켜도 포인트가 남는다.** 관대 디코더에 줄을 안 더하면 저장은 되고 읽기만 빠진다.
    func testResearchPointsSurviveARestart() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("prof-save-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1), now: { self.now })
        store.mutate { $0.researchPoints = 137 }

        let reloaded = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1), now: { self.now })
        XCTAssertEqual(reloaded.state.researchPoints, 137, "다시 켜니 포인트가 사라졌다")
    }

    /// 말이 안 되는 값은 경계에서 자른다 — 산술에 쓰이는 수치라 `Int.max` 가 들어오면 이후
    /// 덧셈이 Swift 오버플로 트랩으로 프로세스를 죽이고, 재기동해도 같은 파일을 읽어 또 죽는다.
    func testAbsurdResearchPointsAreClamped() throws {
        let json = #"{"researchPoints": 9223372036854775807}"#
        let state = try JSONDecoder().decode(PlayerState.self, from: Data(json.utf8))
        XCTAssertLessThanOrEqual(state.researchPoints, 1_000_000)
        XCTAssertGreaterThanOrEqual(state.researchPoints, 0)

        let negative = #"{"researchPoints": -5}"#
        XCTAssertEqual(try JSONDecoder().decode(PlayerState.self,
                                                from: Data(negative.utf8)).researchPoints, 0)
    }

    // MARK: 보내기

    /// **파트너는 못 보낸다.** 값 자체가 nil 이라 화면이 버튼을 못 만든다.
    func testThePartnerCannotBeSent() {
        let store = makeStore()
        let partner = make(.common, path: [1])
        store.addForTesting(partner)
        store.setPartner(partner.id)

        XCTAssertNil(store.releaseValue(partner))
        XCTAssertNil(store.releaseToProfessor(individualID: partner.id))
        XCTAssertEqual(store.state.box.count, 1, "파트너가 사라졌다")
        XCTAssertEqual(store.state.researchPoints, 0)
    }

    /// 보내면 박스에서 빠지고 포인트가 들어온다.
    func testSendingRemovesTheIndividualAndPaysPoints() {
        let store = makeStore()
        let keep = make(.common, path: [1])
        let send = make(.epic, path: [4, 5, 6])
        store.addForTesting(keep)
        store.addForTesting(send)
        store.setPartner(keep.id)

        XCTAssertEqual(store.releaseValue(send), 36)
        XCTAssertEqual(store.releaseToProfessor(individualID: send.id), 36)
        XCTAssertEqual(store.state.box.map(\.id), [keep.id], "박스에서 안 빠졌다")
        XCTAssertEqual(store.state.researchPoints, 36)
    }

    /// **도감은 그대로다.** 도감은 만난 기록이지 소유 기록이 아니다.
    func testSendingKeepsTheDexEntry() {
        let store = makeStore()
        let send = make(.rare, path: [25])
        store.addForTesting(send)
        store.mutate { $0.dex.insert(25) }

        store.releaseToProfessor(individualID: send.id)
        XCTAssertTrue(store.state.dex.contains(25), "도감에서 지워졌다")
    }

    /// 박스에 없는 개체는 아무 일도 안 일어난다.
    func testSendingAnUnknownIndividualDoesNothing() {
        let store = makeStore()
        XCTAssertNil(store.releaseToProfessor(individualID: UUID()))
        XCTAssertEqual(store.state.researchPoints, 0)
    }

    // MARK: 딸린 정리 — 부화 감면

    /// **유일한 불꽃몸을 보내면 감면이 끝난다.** 감면은 지금 가지고 있는 동안만 걸린다 —
    /// 보내는 대가로 이후에 거는 알은 더 이상 절반을 못 받는다. 다만 **소급되지는 않는다**:
    /// 보내기 전에 이미 걸어 둔 알은 그때 받은 감면을 그대로 유지한다.
    func testSendingTheOnlyWarmPokemonEndsTheDiscountForFutureEggs() {
        let store = makeStore()
        let keep = make(.common, path: [1])
        store.addForTesting(keep)
        store.setPartner(keep.id)
        // 마그마그(불꽃몸 계열).
        let slugma = make(.common, path: [218])
        store.addForTesting(slugma)
        XCTAssertTrue(HatchSpeedup.present(in: store.state.box))

        // 보내기 **전**에 건 알 — 이미 받은 감면은 소급해서 뺏기지 않는다.
        let discounted = store.placeEgg(grade: .common, speciesID: 1, shiny: false)
        let discountedHatchesAt = discounted?.hatchesAt
        XCTAssertEqual(discountedHatchesAt?.timeIntervalSince(now) ?? 0,
                       EggBalance.duration(.common) * HatchSpeedup.multiplier, accuracy: 1,
                       "이미 걸 때는 감면을 못 받았다")

        store.releaseToProfessor(individualID: slugma.id)

        XCTAssertFalse(HatchSpeedup.present(in: store.state.box), "보냈는데 감면이 남았다")
        XCTAssertEqual(store.state.eggs.first { $0.id == discounted?.id }?.hatchesAt,
                       discountedHatchesAt, "이미 건 알의 감면이 소급 취소됐다")

        let egg = store.placeEgg(grade: .common, speciesID: 1, shiny: false)
        XCTAssertEqual(egg?.hatchesAt.timeIntervalSince(now) ?? 0,
                       EggBalance.duration(.common), accuracy: 1,
                       "보낸 뒤에 건 알이 아직도 감면을 받는다")
    }

    // MARK: 결정적 굴림

    /// **`String.hashValue` 를 쓰면 안 된다** — Swift 기본 해시는 프로세스마다 무작위로
    /// 시딩되므로 앱을 껐다 켤 때마다 다른 값이 나온다. FNV-1a 는 어디서든 같은 값이다.
    func testTheHashIsStableAndNotSwiftsOwn() {
        XCTAssertEqual(ProfessorRoll.hash("2026-08-11"), ProfessorRoll.hash("2026-08-11"))
        XCTAssertNotEqual(ProfessorRoll.hash("2026-08-11"), ProfessorRoll.hash("2026-08-12"))
        // FNV-1a 64비트 표준 벡터 — 구현이 슬쩍 바뀌면 여기서 걸린다.
        XCTAssertEqual(ProfessorRoll.hash(""), 0xcbf2_9ce4_8422_2325)
    }

    /// 굴림은 0…1 안에 있고, 같은 (날짜·자리·용도) 면 언제나 같다.
    func testRollsAreInRangeAndRepeatable() {
        for slot in 0..<3 {
            for salt in [ProfessorRoll.Salt.grade, ProfessorRoll.Salt.species, ProfessorRoll.Salt.shiny] {
                let a = ProfessorRoll.unit(date: "2026-08-11", slot: slot, salt: salt)
                XCTAssertEqual(a, ProfessorRoll.unit(date: "2026-08-11", slot: slot, salt: salt))
                XCTAssertGreaterThanOrEqual(a, 0)
                XCTAssertLessThan(a, 1)
            }
        }
    }

    /// **자리와 용도가 다르면 값도 달라야 한다.** 같으면 세 자리가 똑같은 포켓몬이 되거나
    /// 등급과 이로치가 붙어 움직인다.
    func testRollsDifferBySlotAndSalt() {
        let bySlot = (0..<3).map { ProfessorRoll.unit(date: "d", slot: $0, salt: ProfessorRoll.Salt.grade) }
        XCTAssertEqual(Set(bySlot).count, 3, "자리마다 굴림이 같다")
        let bySalt = [ProfessorRoll.Salt.grade, ProfessorRoll.Salt.species, ProfessorRoll.Salt.shiny]
            .map { ProfessorRoll.unit(date: "d", slot: 0, salt: $0) }
        XCTAssertEqual(Set(bySalt).count, 3, "용도마다 굴림이 같다")
    }

    // MARK: 오늘의 제안

    private func index() -> [BaseSpecies] {
        [BaseSpecies(id: 1, captureRate: 255, isLegendary: false, isMythical: false),
         BaseSpecies(id: 4, captureRate: 45, isLegendary: false, isMythical: false),
         BaseSpecies(id: 25, captureRate: 190, isLegendary: false, isMythical: false),
         BaseSpecies(id: 133, captureRate: 35, isLegendary: false, isMythical: false),
         BaseSpecies(id: 150, captureRate: 3, isLegendary: true, isMythical: false)]
    }

    /// 날짜가 정해진 뒤 준비하면 3마리가 뜬다.
    func testPreparingTodaysOffers() {
        let store = makeStore()
        store.update(todayTokens: 0, todayDate: "2026-08-11", hasUsageData: true)
        store.refreshProfessorOffers(index: index())
        XCTAssertEqual(store.state.professorOffers.count, 3)
        XCTAssertEqual(store.state.professorOfferDate, "2026-08-11")
        XCTAssertTrue(store.state.professorOffers.allSatisfy { !$0.claimed })
    }

    /// **같은 날 두 번 준비해도 같은 3마리.** 인덱스가 늦게 와서 다시 부르는 일이 실제로 있다.
    func testPreparingTwiceInADayKeepsTheSameThree() {
        let store = makeStore()
        store.update(todayTokens: 0, todayDate: "2026-08-11", hasUsageData: true)
        store.refreshProfessorOffers(index: index())
        let first = store.state.professorOffers.map(\.individual.speciesID)
        store.refreshProfessorOffers(index: index())
        XCTAssertEqual(store.state.professorOffers.map(\.individual.speciesID), first)
    }

    /// **앱을 껐다 켜도 같은 3마리.** 여기가 `String.hashValue` 를 썼을 때 깨지는 자리다 —
    /// 저장된 제안을 지우고 새 프로세스가 다시 굴려도 같은 종이 나와야 한다.
    func testTheSameDayRollsTheSameThreeInAFreshStore() {
        func speciesOfFreshStore() -> [Int] {
            let s = makeStore()
            s.update(todayTokens: 0, todayDate: "2026-08-11", hasUsageData: true)
            s.refreshProfessorOffers(index: index())
            return s.state.professorOffers.map(\.individual.speciesID)
        }
        XCTAssertEqual(speciesOfFreshStore(), speciesOfFreshStore())
    }

    /// 날짜가 바뀌면 새로 뽑는다.
    func testANewDayRollsNewOffers() {
        let store = makeStore()
        store.update(todayTokens: 0, todayDate: "2026-08-11", hasUsageData: true)
        store.refreshProfessorOffers(index: index())
        let first = store.state.professorOffers.map(\.individual.speciesID)

        store.update(todayTokens: 1, todayDate: "2026-08-12", hasUsageData: true)
        store.refreshProfessorOffers(index: index())
        XCTAssertEqual(store.state.professorOfferDate, "2026-08-12")
        XCTAssertNotEqual(store.state.professorOffers.map(\.individual.speciesID), first)
    }

    /// 인덱스가 아직 없으면 아무것도 안 한다 — 빈 후보로 굴리면 크래시다.
    func testAnEmptyIndexPreparesNothing() {
        let store = makeStore()
        store.update(todayTokens: 0, todayDate: "2026-08-11", hasUsageData: true)
        store.refreshProfessorOffers(index: [])
        XCTAssertTrue(store.state.professorOffers.isEmpty)
        XCTAssertEqual(store.state.professorOfferDate, "")
    }

    // MARK: 교환

    private func preparedStore() -> PlayerStore {
        let store = makeStore()
        store.update(todayTokens: 0, todayDate: "2026-08-11", hasUsageData: true)
        store.refreshProfessorOffers(index: index())
        return store
    }

    /// 포인트가 모자라면 교환 실패 + **포인트 미차감**.
    func testAcceptingWithoutEnoughPointsChangesNothing() {
        let store = preparedStore()
        let offer = store.state.professorOffers[0]
        XCTAssertNil(store.acceptProfessorOffer(offerID: offer.id))
        XCTAssertEqual(store.state.researchPoints, 0)
        XCTAssertTrue(store.state.box.isEmpty)
        XCTAssertFalse(store.state.professorOffers[0].claimed)
    }

    /// 교환하면 값을 치르고 박스와 도감에 들어간다. **보이던 개체 그대로**여야 한다.
    func testAcceptingTakesTheExactPokemonShown() {
        let store = preparedStore()
        store.mutate { $0.researchPoints = 1000 }
        let offer = store.state.professorOffers[0]
        let price = ProfessorBalance.price(grade: offer.individual.grade)

        let taken = store.acceptProfessorOffer(offerID: offer.id)
        XCTAssertEqual(taken?.speciesID, offer.individual.speciesID)
        XCTAssertEqual(taken?.shiny, offer.individual.shiny)
        XCTAssertEqual(taken?.nature, offer.individual.nature)
        XCTAssertEqual(taken?.grade, offer.individual.grade)
        XCTAssertEqual(store.state.researchPoints, 1000 - price)
        XCTAssertEqual(store.state.box.count, 1)
        XCTAssertTrue(store.state.dex.contains(offer.individual.speciesID))
    }

    /// **교환한 자리는 그날 다시 안 채워진다** — 자리는 남고 표시만 붙는다.
    func testAClaimedOfferStaysClaimedForTheDay() {
        let store = preparedStore()
        store.mutate { $0.researchPoints = 1000 }
        let offer = store.state.professorOffers[0]
        store.acceptProfessorOffer(offerID: offer.id)

        XCTAssertEqual(store.state.professorOffers.count, 3, "자리가 없어졌다")
        XCTAssertTrue(store.state.professorOffers[0].claimed)
        XCTAssertNil(store.acceptProfessorOffer(offerID: offer.id), "두 번 데려갔다")
        XCTAssertEqual(store.state.box.count, 1)

        store.refreshProfessorOffers(index: index())
        XCTAssertTrue(store.state.professorOffers[0].claimed, "같은 날에 되살아났다")
    }

    /// **두 재화가 안 섞인다** — 포인트로 알을 못 사고, 토큰으로 제안을 못 산다.
    func testPointsAndTokensNeverMix() {
        let store = preparedStore()
        store.mutate { $0.researchPoints = 1000 }
        let walletBefore = store.state.wallet
        store.acceptProfessorOffer(offerID: store.state.professorOffers[0].id)
        XCTAssertEqual(store.state.wallet, walletBefore, "제안을 토큰으로 샀다")

        let pointsBefore = store.state.researchPoints
        store.update(todayTokens: EggBalance.drawPrice * 2, todayDate: "2026-08-11",
                     hasUsageData: true)
        store.startEgg(grade: .common, speciesID: 1, shiny: false)
        XCTAssertEqual(store.state.researchPoints, pointsBefore, "알을 포인트로 샀다")
    }

    /// 저장 왕복 — 오늘의 제안이 재기동 후에도 남는다.
    func testOffersSurviveARestart() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("prof-offers-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1), now: { self.now })
        store.update(todayTokens: 0, todayDate: "2026-08-11", hasUsageData: true)
        store.refreshProfessorOffers(index: index())
        let species = store.state.professorOffers.map(\.individual.speciesID)

        let reloaded = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1), now: { self.now })
        XCTAssertEqual(reloaded.state.professorOffers.map(\.individual.speciesID), species)
        XCTAssertEqual(reloaded.state.professorOfferDate, "2026-08-11")
    }

    /// 가격표.
    func testOfferPrices() {
        XCTAssertEqual(ProfessorBalance.price(grade: .common), 10)
        XCTAssertEqual(ProfessorBalance.price(grade: .rare), 25)
        XCTAssertEqual(ProfessorBalance.price(grade: .epic), 60)
        XCTAssertEqual(ProfessorBalance.price(grade: .legendary), 200)
    }
}
