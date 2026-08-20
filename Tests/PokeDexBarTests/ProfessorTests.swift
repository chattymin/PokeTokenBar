import AppKit
import SwiftUI
import XCTest
@testable import PokeDexBar

/// 제안 화면 렌더 테스트가 쓰는 프로바이더 — 빈 인덱스를 돌려줘 `ProfessorOfferSection.task` 가
/// `refreshProfessorOffers` 를 다시 부르지 않게 한다(`DiscoveryTests` 의 `StubDiscoveryProvider` 와
/// 같은 패턴). 미리 심어 둔 `professorOffers` 를 렌더 중에 덮어쓰면 무엇을 확인하는지가 흐려진다.
private struct StubOfferProvider: PokeProviding {
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: baseSpeciesID, tree: EvoNode(speciesID: baseSpeciesID, children: []),
                rarity: .common, names: [:])
    }
}

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

    /// **값은 레벨을 따른다.** 100레벨이 한 단계를 통째로 더 얹는 것과 같다.
    func testReleasePointsFollowTheLevel() {
        func made(_ level: Int) -> Individual {
            Individual(baseID: 4, speciesID: 4, pathIDs: [4], nature: .hardy,
                       exp: GrowthRate.mediumFast.totalExp(at: level), obtainedAt: now,
                       grade: .epic, growthRate: .mediumFast)
        }
        XCTAssertEqual(ReleaseBalance.points(for: made(1)), 12)    // 12 × (0 + 1 + 0.01)
        XCTAssertEqual(ReleaseBalance.points(for: made(50)), 18)   // 12 × (0 + 1 + 0.50)
        XCTAssertEqual(ReleaseBalance.points(for: made(100)), 24)  // 12 × (0 + 1 + 1.00)
    }

    /// 진화 단계도 그대로 값에 실린다 — 레벨만 보는 구현이면 여기서 걸린다.
    func testReleasePointsStillCountTheStages() {
        let grown = Individual(baseID: 4, speciesID: 6, pathIDs: [4, 5, 6], nature: .hardy,
                               exp: GrowthRate.mediumFast.totalExp(at: 100), obtainedAt: now,
                               grade: .epic, growthRate: .mediumFast)
        XCTAssertEqual(ReleaseBalance.points(for: grown), 48)      // 12 × (2 + 1 + 1.00)
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
        store.mutate { $0.dexForms.insert("25") }

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
                let a = ProfessorRoll.unit(seed: 7, date: "2026-08-11", slot: slot, salt: salt)
                XCTAssertEqual(a, ProfessorRoll.unit(seed: 7, date: "2026-08-11", slot: slot, salt: salt))
                XCTAssertGreaterThanOrEqual(a, 0)
                XCTAssertLessThan(a, 1)
            }
        }
    }

    /// **자리와 용도가 다르면 값도 달라야 한다.** 같으면 세 자리가 똑같은 포켓몬이 되거나
    /// 등급과 이로치가 붙어 움직인다.
    func testRollsDifferBySlotAndSalt() {
        let bySlot = (0..<3).map { ProfessorRoll.unit(seed: 7, date: "d", slot: $0, salt: ProfessorRoll.Salt.grade) }
        XCTAssertEqual(Set(bySlot).count, 3, "자리마다 굴림이 같다")
        let bySalt = [ProfessorRoll.Salt.grade, ProfessorRoll.Salt.species, ProfessorRoll.Salt.shiny]
            .map { ProfessorRoll.unit(seed: 7, date: "d", slot: 0, salt: $0) }
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

        store.openProfessorOffer(offerID: offer.id)
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
        store.openProfessorOffer(offerID: offer.id)
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

    // MARK: 사람마다 다른 제안 (2026-08-12 회귀)
    //
    // 제안이 날짜·자리·용도로만 결정돼 **같은 날 모든 설치가 같은 세 마리**를 받았다. 기존
    // 테스트가 못 걸른 이유는 분명하다 — `unit` 에 사용자가 아예 없어서 "다른 사람끼리 다른가"를
    // **물어볼 수조차 없었다**. 안정성(같은 날 = 같은 셋)만 잠겨 있었고, 그 테스트는 결함이
    // 있을 때도 똑같이 통과한다. 아래 셋이 그 질문을 처음으로 던진다.

    /// **시드가 다르면 굴림이 다르다.** 다른 축(날짜·자리·용도)은 이미 잠겨 있으므로
    /// 여기서는 시드만 바꾼다 — 다른 것을 같이 바꾸면 무엇이 값을 갈랐는지 알 수 없다.
    func testRollsDifferBySeed() {
        let bySeed = (1...8).map {
            ProfessorRoll.unit(seed: UInt64($0), date: "d", slot: 0, salt: ProfessorRoll.Salt.grade)
        }
        XCTAssertEqual(Set(bySeed).count, 8, "시드가 달라도 굴림이 같다 — 전원이 같은 제안을 받는다")
    }

    /// **다른 두 사용자가 같은 날 다른 제안을 받는다.** 후보가 5종뿐이라 하루치는 우연히
    /// 겹칠 수 있어 여러 날을 이어 붙여 비교한다 — 열흘이 통째로 같으면 그건 우연이 아니다.
    func testTwoPlayersGetDifferentOffersOnTheSameDays() {
        func offers(of store: PlayerStore) -> [String] {
            (11...20).map { day in
                store.update(todayTokens: day, todayDate: "2026-08-\(day)", hasUsageData: true)
                store.refreshProfessorOffers(index: index())
                return store.state.professorOffers
                    .map { "\($0.individual.speciesID)/\($0.individual.grade)/\($0.individual.nature)" }
                    .joined(separator: ",")
            }
        }
        let mine = offers(of: makeStore(seed: 1))
        let theirs = offers(of: makeStore(seed: 99))

        XCTAssertEqual(mine.count, 10)
        XCTAssertNotEqual(mine, theirs, "두 사용자가 열흘 내내 같은 제안을 받는다")
    }

    /// **시드는 세이브에 산다 — 파일을 옮기면 따라간다.** 설정(UserDefaults)에 뒀다면 세이브를
    /// 옮긴 순간 제안이 통째로 갈린다. 파일만 복사한 새 스토어가(난수기는 일부러 다르게 준다)
    /// 같은 제안을 뽑아야 한다.
    func testTheSeedTravelsWithTheSaveFile() throws {
        let origin = FileManager.default.temporaryDirectory
            .appendingPathComponent("prof-seed-a-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: origin, rng: SeededRNG(seed: 1), now: { self.now })
        store.update(todayTokens: 0, todayDate: "2026-08-11", hasUsageData: true)
        store.refreshProfessorOffers(index: index())
        let species = store.state.professorOffers.map(\.individual.speciesID)

        // 다른 기기로 세이브만 옮긴 상황 — 난수기가 다르므로 시드를 세이브에서 못 읽으면 갈린다.
        let moved = origin.deletingLastPathComponent()
            .appendingPathComponent("prof-seed-b-\(UUID().uuidString).json")
        try FileManager.default.copyItem(at: origin, to: moved)
        let elsewhere = PlayerStore(fileURL: moved, rng: SeededRNG(seed: 12345), now: { self.now })
        XCTAssertEqual(elsewhere.state.offerSeed, store.state.offerSeed, "시드가 안 따라왔다")

        // 옮긴 쪽에서 다시 굴려도(오늘 치를 지우고) 같은 셋이어야 한다.
        elsewhere.mutate { $0.professorOfferDate = "" }
        elsewhere.refreshProfessorOffers(index: index())
        XCTAssertEqual(elsewhere.state.professorOffers.map(\.individual.speciesID), species,
                       "세이브를 옮겼더니 제안이 갈렸다")
    }

    /// **시드는 첫 기동에 생겨 저장된다.** 저장을 빼먹으면 매 기동 새로 만들어져 오늘의 제안이
    /// 앱을 껐다 켤 때마다 바뀐다 — 결정적 굴림을 쓴 이유가 통째로 사라진다.
    func testTheSeedIsCreatedOnceAndPersisted() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("prof-seed-\(UUID().uuidString).json")
        let first = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1), now: { self.now })
        XCTAssertNotEqual(first.state.offerSeed, 0, "시드가 안 만들어졌다")

        // 난수기를 일부러 다르게 준다 — 저장된 값을 안 읽으면 여기서 갈린다.
        let second = PlayerStore(fileURL: url, rng: SeededRNG(seed: 777), now: { self.now })
        XCTAssertEqual(second.state.offerSeed, first.state.offerSeed, "기동할 때마다 시드가 새로 생긴다")
    }

    /// **개인화는 내일부터 — 오늘 치는 안 건드린다.** 1.6.0 세이브가 올라오는 그 순간
    /// 이미 열어 보거나 데려온 자리가 다른 포켓몬으로 바뀌면 안 된다.
    func testUpgradingAnOldSaveKeepsTodaysOffersAndPersonalisesTomorrow() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("prof-legacy-\(UUID().uuidString).json")
        let old = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1), now: { self.now })
        old.update(todayTokens: 0, todayDate: "2026-08-11", hasUsageData: true)
        old.refreshProfessorOffers(index: index())
        let today = old.state.professorOffers.map(\.individual.speciesID)
        // 시드가 없던 시절의 세이브로 되돌린다 — 업그레이드 직전 상태.
        old.mutate { $0.offerSeed = 0 }

        let upgraded = PlayerStore(fileURL: url, rng: SeededRNG(seed: 42), now: { self.now })
        XCTAssertNotEqual(upgraded.state.offerSeed, 0, "업그레이드된 세이브에 시드가 안 생겼다")
        upgraded.refreshProfessorOffers(index: index())
        XCTAssertEqual(upgraded.state.professorOffers.map(\.individual.speciesID), today,
                       "오늘 치가 다시 굴려졌다 — 이미 연 카드가 다른 포켓몬으로 바뀐다")

        upgraded.update(todayTokens: 1, todayDate: "2026-08-12", hasUsageData: true)
        upgraded.refreshProfessorOffers(index: index())
        XCTAssertEqual(upgraded.state.professorOfferDate, "2026-08-12", "다음 날 제안이 안 갈렸다")
    }

    /// 가격표.
    func testOfferPrices() {
        XCTAssertEqual(ProfessorBalance.price(grade: .common), 10)
        XCTAssertEqual(ProfessorBalance.price(grade: .rare), 25)
        XCTAssertEqual(ProfessorBalance.price(grade: .epic), 60)
        XCTAssertEqual(ProfessorBalance.price(grade: .legendary), 200)
    }

    // MARK: 보내기 화면

    /// 확인 단계 — 되돌릴 수 없는 조작이라 한 번에 안 나간다. 이로치·전설은 한 단계 더.
    func testConfirmStepsByRarity() {
        XCTAssertEqual(IndividualDetailView.releaseConfirmSteps(shiny: false, grade: .common), 1)
        XCTAssertEqual(IndividualDetailView.releaseConfirmSteps(shiny: false, grade: .rare), 1)
        XCTAssertEqual(IndividualDetailView.releaseConfirmSteps(shiny: true, grade: .common), 2,
                       "이로치를 한 번에 보낼 수 있다")
        XCTAssertEqual(IndividualDetailView.releaseConfirmSteps(shiny: false, grade: .legendary), 2,
                       "전설을 한 번에 보낼 수 있다")
        XCTAssertEqual(IndividualDetailView.releaseConfirmSteps(shiny: true, grade: .legendary), 2)
    }

    /// 상세 화면이 보내기 경로에 닿아 있다.
    func testTheDetailViewReachesTheReleasePath() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent(
            "Sources/PokeDexBar/UI/IndividualDetailView.swift"), encoding: .utf8)
        XCTAssertTrue(text.contains("releaseToProfessor"), "상세에 보내기 버튼이 없다")
        XCTAssertFalse(text.contains(".help("), "안 뜨는 툴팁이 들어왔다")
    }

    /// 문구가 세 언어를 다 채운다.
    func testReleaseStringsCoverAllThreeLanguages() {
        for lang in AppLanguage.allCases {
            let l = L(lang)
            XCTAssertFalse(l.sendToProfessor(4).isEmpty, "\(lang)")
            XCTAssertFalse(l.sendConfirmNoReturn.isEmpty, "\(lang)")
            XCTAssertFalse(l.sendConfirmAgain.isEmpty, "\(lang)")
            XCTAssertFalse(l.sendCancel.isEmpty, "\(lang)")
            XCTAssertFalse(l.sendNow.isEmpty, "\(lang)")
        }
    }

    /// **확인 화면의 문구 자체를 판정하는 순수 함수.** `releaseConfirmSteps` 만 테스트하고
    /// 화면이 그 값을 어떻게 문구로 옮기는지는 안 잰 게 fix round 1 의 결함이 새어 나간 자리다 —
    /// "몇 번째로 누르면 끝나는지"(`releaseStep < steps`)로 문구를 갈랐더니, 1단계짜리 개체
    /// (일반·희귀)는 확인 화면에 들어온 순간 `releaseStep` 이 이미 마지막이라 되돌릴 수 없다는
    /// 경고가 구조적으로 안 뜰 수 있었다. 이 테스트는 **몇 번째로 묻는 화면인지**로 갈라야
    /// 함을 고정한다 — 1단계·2단계 개체 모두 처음 묻는 화면(step 1)은 항상 경고여야 한다.
    func testFirstConfirmScreenShowsTheIrreversibilityWarning() {
        let l = L(.ko)
        // 1단계짜리(일반·희귀)든 2단계짜리(이로치·전설)든, **처음 묻는 화면**은 항상 경고다.
        XCTAssertEqual(IndividualDetailView.releaseConfirmText(step: 1, l: l), l.sendConfirmNoReturn,
                       "처음 묻는 화면인데 되돌릴 수 없다는 경고가 아니다")
        // 두 번째로 묻는 화면(이로치·전설에만 있다)만 반복 문구다.
        XCTAssertEqual(IndividualDetailView.releaseConfirmText(step: 2, l: l), l.sendConfirmAgain,
                       "두 번째로 묻는 화면인데 반복 문구가 아니다")
    }

    // MARK: 보내기 화면 — 실제로 눌러 본다
    //
    // 위의 `releaseConfirmSteps`/`releaseConfirmText` 는 순수 함수만 잠근다 — 값은 맞는데 화면이
    // 그 값을 잘못 배선하는 결함(fix round 1)은 못 잡는다. `FoundEggTests.renderedDetailButtons`
    // 와 같은 패턴으로 실제 뷰를 그리고 버튼을 눌러, 배선 자체를 검증한다.

    /// `IndividualDetailView` 를 실제로 그린다. `AnyView` 로 지우는 이유는 이 host 를 여러 번
    /// 다시 레이아웃해(=버튼을 누른 뒤 상태 전환을 반영해) 재사용해야 하기 때문이다.
    private func hostedDetail(_ store: PlayerStore, individual: Individual) -> NSHostingView<AnyView> {
        DetailActionButton.resetConstructed()
        let host = NSHostingView(rootView: AnyView(IndividualDetailView(
            store: store, individual: individual, line: nil, onNeedLine: { _ in }, onBack: {}
        ).frame(width: PopoverMetrics.width)))
        host.layoutSubtreeIfNeeded()
        return host
    }

    /// 버튼을 누른 뒤(=상태가 바뀐 뒤) 지금 화면에 뜬 버튼을 다시 읽는다.
    private func currentButtons(_ host: NSHostingView<AnyView>) -> [(title: String, action: () -> Void)] {
        DetailActionButton.resetConstructed()
        host.layoutSubtreeIfNeeded()
        return DetailActionButton.constructed
    }

    /// **한 번만 눌러서는 안 나간다 — 이로치.** 초기 버튼 한 번은 확인 화면으로 넘어갈 뿐이어야
    /// 한다. fix round 1 은 문구만 틀렸지 조작 자체는 안 샜지만, 배선이 그 결함과 같은 자리에
    /// 있었으므로 조작이 새는지도 따로 잰다.
    func testASinglePressOnAShinyDoesNotSendIt() {
        let store = makeStore()
        let keep = make(.common, path: [1])
        store.addForTesting(keep)
        store.setPartner(keep.id)
        let shiny = Individual(baseID: 25, speciesID: 25, pathIDs: [25], shiny: true,
                               nature: .hardy, exp: 0, obtainedAt: now, grade: .rare)
        store.addForTesting(shiny)
        let points = store.releaseValue(shiny)!

        _ = hostedDetail(store, individual: shiny)
        guard let send = DetailActionButton.constructed.first(where: { $0.title == store.l.sendToProfessor(points) }) else {
            return XCTFail("보내기 버튼이 안 보인다")
        }
        send.action()

        XCTAssertEqual(Set(store.state.box.map(\.id)), Set([keep.id, shiny.id]), "한 번 눌렀는데 박스에서 빠졌다")
        XCTAssertEqual(store.state.researchPoints, 0, "한 번 눌렀는데 포인트가 들어왔다")
    }

    /// **한 번만 눌러서는 안 나간다 — 전설.** 위와 같은 이유, 등급 경로로 한 번 더.
    func testASinglePressOnALegendaryDoesNotSendIt() {
        let store = makeStore()
        let keep = make(.common, path: [1])
        store.addForTesting(keep)
        store.setPartner(keep.id)
        let legendary = make(.legendary, path: [150])
        store.addForTesting(legendary)
        let points = store.releaseValue(legendary)!

        _ = hostedDetail(store, individual: legendary)
        guard let send = DetailActionButton.constructed.first(where: { $0.title == store.l.sendToProfessor(points) }) else {
            return XCTFail("보내기 버튼이 안 보인다")
        }
        send.action()

        XCTAssertEqual(Set(store.state.box.map(\.id)), Set([keep.id, legendary.id]), "한 번 눌렀는데 박스에서 빠졌다")
        XCTAssertEqual(store.state.researchPoints, 0, "한 번 눌렀는데 포인트가 들어왔다")
    }

    /// **전체 단계를 다 누르면 실제로 나간다.** 일반 개체는 1단계라 초기 버튼 → 보내기 두 번이면
    /// 끝난다. 박스에서 사라지고 포인트가 들어와야 한다 — `onBack` 은 뷰 레벨이라 여기서
    /// 직접 못 재지만, 사라진 개체의 상세에 `onBack` 없이 남아 있을 수는 없다는 전제만 남긴다.
    func testTheFullConfirmSequenceSendsAnOrdinaryIndividual() {
        let store = makeStore()
        let keep = make(.common, path: [1])
        store.addForTesting(keep)
        store.setPartner(keep.id)
        let send = make(.common, path: [1, 2])
        store.addForTesting(send)
        let points = store.releaseValue(send)!

        let host = hostedDetail(store, individual: send)
        guard let firstButton = DetailActionButton.constructed.first(where: { $0.title == store.l.sendToProfessor(points) }) else {
            return XCTFail("보내기 버튼이 안 보인다")
        }
        firstButton.action()   // 0단계 → 1단계(확인 화면)

        let confirmButtons = currentButtons(host)
        guard let sendNow = confirmButtons.first(where: { $0.title == store.l.sendNow }) else {
            return XCTFail("확인 화면에 보내기 버튼이 없다: \(confirmButtons.map(\.title))")
        }
        XCTAssertNotNil(confirmButtons.first(where: { $0.title == store.l.sendCancel }),
                        "확인 화면에 그만두기 버튼이 없다")
        sendNow.action()   // 일반 개체는 1단계라 이 한 번으로 끝난다

        XCTAssertFalse(store.state.box.contains { $0.id == send.id }, "다 눌렀는데 박스에 남아 있다")
        XCTAssertTrue(store.state.box.contains { $0.id == keep.id }, "관계 없는 개체까지 사라졌다")
        XCTAssertEqual(store.state.researchPoints, points, "다 눌렀는데 포인트가 안 들어왔다")
    }

    /// **파트너는 보내기 버튼 자체가 없다.** `releaseValue` 가 nil 이라 `releaseSection` 이 아무것도
    /// 안 그린다 — 값을 감춰서 막는 게 아니라 버튼 구성이 애초에 없어야 한다.
    func testThePartnerNeverGetsAReleaseButton() {
        let store = makeStore()
        let partner = make(.common, path: [1])
        store.addForTesting(partner)
        store.setPartner(partner.id)
        // 파트너가 아니었다면 받았을 점수 — 이 문구가 화면 어디에도 없어야 한다.
        let wouldBePoints = ReleaseBalance.points(for: partner)

        _ = hostedDetail(store, individual: partner)

        XCTAssertNil(DetailActionButton.constructed.first(where: { $0.title == store.l.sendToProfessor(wouldBePoints) }),
                     "파트너인데 보내기 버튼이 떴다: \(DetailActionButton.constructed.map(\.title))")
    }

    // MARK: 딸린 정리 — 부화 감면(제안 경로)

    /// **제안으로 데려온 개체도 감면을 건다.** 박스에 개체가 들어오는 경로는 스타터·부화·진화·
    /// `acceptProfessorOffer` 넷인데, 앞의 셋은 `applyHatchSpeedupIfNewlyEarned` 를 부르지만
    /// 제안 교환만 빠져 있었다 — 마그마그를 박사에게서 데려오면 진행 중이던 알이 그대로였다
    /// (같은 마그마그를 부화로 얻으면 절반이 됐다). 슬러그마는 `HatchSpeedup.species` 의 베이스
    /// 종이자 `pickSpecies` 가 뽑을 수 있는 종이라 실제로 걸리는 경로다.
    func testAcceptingAWarmOfferSpeedsUpAnEggAlreadyInFlight() {
        let store = makeStore()
        let keep = make(.common, path: [1])
        store.addForTesting(keep)
        store.setPartner(keep.id)

        // 이미 걸린 알 — 감면 전 정가로 시작한다.
        let egg = store.placeEgg(grade: .common, speciesID: 1, shiny: false)
        XCTAssertEqual(egg?.hatchesAt.timeIntervalSince(now) ?? 0,
                       EggBalance.duration(.common), accuracy: 1, "감면 없이 시작하지 않았다")

        // 슬러그마(불꽃몸 계열)를 제안에 심어 교환한다.
        store.update(todayTokens: 0, todayDate: "2026-08-11", hasUsageData: true)
        store.mutate {
            $0.professorOfferDate = "2026-08-11"
            $0.professorOffers = [ProfessorOffer(individual: make(.common, path: [218]))]
            $0.researchPoints = 1000
        }
        let offerID = store.state.professorOffers[0].id
        store.openProfessorOffer(offerID: offerID)
        XCTAssertNotNil(store.acceptProfessorOffer(offerID: offerID), "교환이 실패했다")
        XCTAssertTrue(HatchSpeedup.present(in: store.state.box), "박스에 감면 대상이 없다")

        XCTAssertEqual(store.state.eggs.first { $0.id == egg?.id }?.hatchesAt.timeIntervalSince(now) ?? 0,
                       EggBalance.duration(.common) * HatchSpeedup.multiplier, accuracy: 1,
                       "제안으로 데려왔는데 이미 걸린 알의 감면이 안 걸렸다")
    }

    // MARK: 제안 화면 — 실제로 그려 본다
    //
    // 아래 순수 판정(`testOfferPrices` 등)은 값만 잠근다 — 카드가 이름 없이 그려지거나, 버튼이
    // 엉뚱한 제안을 사거나, 데려간 자리에 버튼이 남는 배선 결함은 못 잡는다(같은 부류를 보내기
    // 화면에서 db3a942 가 이미 한 번 냈다). `hostedDetail`/`currentButtons` 와 같은 패턴으로
    // 실제 뷰를 그리고 기록된 동작을 불러 배선 자체를 검증한다.

    private func hostedOfferSection(_ store: PlayerStore) -> NSHostingView<AnyView> {
        ProfessorOfferButton.resetConstructed()
        let host = NSHostingView(rootView: AnyView(
            ProfessorOfferSection(store: store, provider: StubOfferProvider())
                .frame(width: PopoverMetrics.width)))
        host.layoutSubtreeIfNeeded()
        return host
    }

    /// **등급을 서로 다르게 둔다** — 무작위 뽑기(`preparedStore`)는 세 자리가 같은 등급으로 겹칠
    /// 수 있어, 가격으로 카드 수를 세는 근거가 안 된다. `NSHostingView` 는 측정·배치 두 패스로
    /// body 를 두 번 평가하므로(`constructed` 가 매번 그만큼 쌓인다) `.count` 를 그대로 못 쓴다 —
    /// 값(가격) 의 **Set** 으로 세면 중복 패스와 무관하게 "몇 종류의 카드가 떴나"를 잰다.
    ///
    /// 셋 다 **이미 연 채로** 만든다 — 이 아래 테스트들은 카드 본문(스프라이트·이름·가격·버튼)
    /// 렌더를 검증하고, 그건 연 카드에서만 그려진다. 닫힌 채 렌더되는 걸 보고 싶으면
    /// `BlindOfferTests.testAClosedCardSaysNothingAboutWhatIsInside` 를 본다.
    private func threeOfferStore(points: Int) -> PlayerStore {
        let store = makeStore()
        store.mutate {
            $0.professorOfferDate = "2026-08-11"
            $0.professorOffers = [ProfessorOffer(individual: make(.common, path: [1]), opened: true),
                                  ProfessorOffer(individual: make(.rare, path: [4]), opened: true),
                                  ProfessorOffer(individual: make(.epic, path: [25]), opened: true)]
            $0.researchPoints = points
        }
        return store
    }

    /// 세 카드가 실제로 뜨고, 각 카드의 값 치르기 버튼에 그 자리의 가격이 정확히 실린다.
    func testOfferSectionRendersThreeCardsWithCorrectPrices() {
        let store = threeOfferStore(points: 1000)

        _ = hostedOfferSection(store)

        let titles = Set(ProfessorOfferButton.constructed.map(\.title))
        XCTAssertEqual(titles, Set([10, 25, 60].map { store.l.offerPrice($0) }),
                       "카드 세 장의 가격이 안 맞는다: \(ProfessorOfferButton.constructed.map(\.title))")
        XCTAssertTrue(ProfessorOfferButton.constructed.allSatisfy(\.affordable),
                     "포인트가 충분한데 비활성 카드가 있다")
    }

    /// 포인트가 모자란 자리는 버튼이 **비활성으로** 그려진다.
    func testOfferSectionDisablesUnaffordableCards() {
        let store = threeOfferStore(points: 0)

        _ = hostedOfferSection(store)

        XCTAssertEqual(Set(ProfessorOfferButton.constructed.map(\.title)).count, 3,
                       "카드 세 장이 안 떴다: \(ProfessorOfferButton.constructed.map(\.title))")
        XCTAssertTrue(ProfessorOfferButton.constructed.allSatisfy { !$0.affordable },
                     "포인트가 0 인데 활성 버튼이 있다")
    }

    /// 데려간 자리는 버튼 자체가 **안 그려진다** — 흐리게 표시만 남고 "데려갔어요"로 바뀐다.
    func testOfferSectionRecordsNoButtonForAClaimedSlot() {
        let store = threeOfferStore(points: 1000)
        store.mutate { $0.professorOffers[0].claimed = true }   // common(10) 자리

        _ = hostedOfferSection(store)

        let titles = Set(ProfessorOfferButton.constructed.map(\.title))
        XCTAssertFalse(titles.contains(store.l.offerPrice(10)),
                       "데려간 자리에도 버튼이 그려졌다: \(ProfessorOfferButton.constructed.map(\.title))")
        XCTAssertEqual(titles, Set([25, 60].map { store.l.offerPrice($0) }))
    }

    /// **기록된 동작을 실제로 부르면** 그 포켓몬이 박스에 들어온다 — 배선이 살아 있는지의 핵심.
    func testInvokingARecordedActionMovesThePokemonIntoTheBox() {
        let store = threeOfferStore(points: 1000)
        let rareOffer = store.state.professorOffers[1]   // 25P 자리 — 결정적으로 지목한다

        _ = hostedOfferSection(store)
        guard let recorded = ProfessorOfferButton.constructed.first(where: {
            $0.title == store.l.offerPrice(25)
        }) else {
            return XCTFail("25P 카드가 안 떴다: \(ProfessorOfferButton.constructed.map(\.title))")
        }
        recorded.action()

        XCTAssertTrue(store.state.box.contains { $0.speciesID == rareOffer.individual.speciesID },
                     "버튼을 불렀는데 박스에 안 들어왔다")
        XCTAssertTrue(store.state.professorOffers[1].claimed, "버튼을 불렀는데 그 자리가 안 바뀌었다")
    }

    /// 상점이 제안 경로에 닿아 있다 — 안 닿으면 제안을 영원히 못 본다.
    func testTheShopReachesTheOfferSection() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let shop = try String(contentsOf: root.appendingPathComponent(
            "Sources/PokeDexBar/UI/ShopTabView.swift"), encoding: .utf8)
        XCTAssertTrue(shop.contains("ProfessorOfferSection"), "상점에 박사의 제안이 없다")
        let section = try String(contentsOf: root.appendingPathComponent(
            "Sources/PokeDexBar/UI/ProfessorOfferSection.swift"), encoding: .utf8)
        XCTAssertTrue(section.contains("acceptProfessorOffer"), "교환 경로에 안 닿는다")
        XCTAssertTrue(section.contains("refreshProfessorOffers"), "제안을 준비하지 않는다")
        XCTAssertFalse(section.contains(".help("), "안 뜨는 툴팁이 들어왔다")
    }

    /// 문구가 세 언어를 다 채운다.
    func testOfferStringsCoverAllThreeLanguages() {
        for lang in AppLanguage.allCases {
            let l = L(lang)
            XCTAssertFalse(l.professorOffersTitle.isEmpty, "\(lang)")
            XCTAssertFalse(l.researchPoints(7).isEmpty, "\(lang)")
            XCTAssertFalse(l.offerTaken.isEmpty, "\(lang)")
            XCTAssertFalse(l.offerPrice(10).isEmpty, "\(lang)")
        }
    }
}
