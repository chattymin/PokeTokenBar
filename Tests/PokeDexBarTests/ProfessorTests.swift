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
}
