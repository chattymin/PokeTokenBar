import XCTest
@testable import PokeDexBar

final class EggBalanceTests: XCTestCase {
    /// 확률표는 등급별 실제 종 수에 맞춘 값이다 — 누적 경계로 검증한다.
    func testGradeRollBoundaries() {
        XCTAssertEqual(EggBalance.rollGrade(0.0), .common)
        XCTAssertEqual(EggBalance.rollGrade(0.599), .common)
        XCTAssertEqual(EggBalance.rollGrade(0.60), .rare)
        XCTAssertEqual(EggBalance.rollGrade(0.819), .rare)
        XCTAssertEqual(EggBalance.rollGrade(0.82), .epic)
        // 에픽/레전더리 경계 — 레전더리 3% → 2%(도감 미션의 확정권 11장과 맞바꾼 억제,
        // 남은 1%p 는 에픽으로). 경계 바로 안팎을 잠근다.
        XCTAssertEqual(EggBalance.rollGrade(0.979), .epic)
        XCTAssertEqual(EggBalance.rollGrade(0.98), .legendary)
        XCTAssertEqual(EggBalance.rollGrade(0.999), .legendary)
    }

    /// 범위 밖 입력(부동소수 오차)에도 등급이 나온다 — nil 이나 크래시로 새지 않는다.
    func testGradeRollClamps() {
        XCTAssertEqual(EggBalance.rollGrade(-0.5), .common)
        XCTAssertEqual(EggBalance.rollGrade(1.5), .legendary)
    }

    func testDurations() {
        XCTAssertEqual(EggBalance.duration(.common), 30 * 60)
        XCTAssertEqual(EggBalance.duration(.rare), 2 * 3600)
        XCTAssertEqual(EggBalance.duration(.epic), 6 * 3600)
        XCTAssertEqual(EggBalance.duration(.legendary), 24 * 3600)
    }

    /// 등급이 높을수록 오래 걸린다.
    func testDurationsIncreaseWithGrade() {
        XCTAssertLessThan(EggBalance.duration(.common), EggBalance.duration(.rare))
        XCTAssertLessThan(EggBalance.duration(.rare), EggBalance.duration(.epic))
        XCTAssertLessThan(EggBalance.duration(.epic), EggBalance.duration(.legendary))
    }

    /// 슬롯 가격은 4·5·6번째만 있고 그 위는 없다(상한 6).
    func testSlotPriceLadder() {
        XCTAssertEqual(EggBalance.slotPrice(forSlotNumber: 4), 500_000_000)
        XCTAssertEqual(EggBalance.slotPrice(forSlotNumber: 5), 1_500_000_000)
        XCTAssertEqual(EggBalance.slotPrice(forSlotNumber: 6), 4_000_000_000)
        XCTAssertNil(EggBalance.slotPrice(forSlotNumber: 7))
        XCTAssertNil(EggBalance.slotPrice(forSlotNumber: 3), "기본 3슬롯은 사는 게 아니다")
    }

    /// 이로치 분모 — 부적 없음 64, 이로치 부적 48, 무지개 부적 32(겹쳐도 32).
    /// 경계 바로 안팎을 잠근다.
    func testShinyOdds() {
        XCTAssertEqual(EggBalance.shinyDenominator(shinyCharm: false, rainbowCharm: false), 64)
        XCTAssertEqual(EggBalance.shinyDenominator(shinyCharm: true, rainbowCharm: false), 48)
        // 무지개 부적은 이로치 부적의 업그레이드 — 없이도 32, 겹쳐도 32.
        XCTAssertEqual(EggBalance.shinyDenominator(shinyCharm: false, rainbowCharm: true), 32)
        XCTAssertEqual(EggBalance.shinyDenominator(shinyCharm: true, rainbowCharm: true), 32)

        XCTAssertTrue(EggBalance.rollShiny(1.0 / 64 - 0.0001, denominator: 64))
        XCTAssertFalse(EggBalance.rollShiny(1.0 / 64 + 0.0001, denominator: 64))
        XCTAssertTrue(EggBalance.rollShiny(1.0 / 48 - 0.0001, denominator: 48))
        XCTAssertFalse(EggBalance.rollShiny(1.0 / 48 + 0.0001, denominator: 48))
        XCTAssertTrue(EggBalance.rollShiny(1.0 / 32 - 0.0001, denominator: 32))
        XCTAssertFalse(EggBalance.rollShiny(1.0 / 32 + 0.0001, denominator: 32))
    }

    /// 부적은 확률을 낮추지 않는다 — 같은 굴림이면 분모가 작은 쪽이 더 자주 이로치다.
    func testCharmNeverHurts() {
        for step in 0...100 {
            let roll = Double(step) / 100
            if EggBalance.rollShiny(roll, denominator: 64) {
                XCTAssertTrue(EggBalance.rollShiny(roll, denominator: 48))
                XCTAssertTrue(EggBalance.rollShiny(roll, denominator: 32))
            }
            if EggBalance.rollShiny(roll, denominator: 48) {
                XCTAssertTrue(EggBalance.rollShiny(roll, denominator: 32))
            }
        }
    }

    /// 기본 슬롯 수는 `EggBalance.baseSlots` 와 `PlayerState().slots` 두 리터럴로 따로 적혀
    /// 있다(주석으로만 연결) — 이 테스트가 둘을 묶어 드리프트를 막는다.
    func testBaseSlotsMatchesPlayerStateDefault() {
        XCTAssertEqual(EggBalance.baseSlots, PlayerState().slots)
    }

    // MARK: 뽑기 종 선택 (EggBalance.pickSpecies)

    /// 레전더리 등급 뽑기는 실제로 전설/미시컬 종만 후보로 삼는다 — 회귀 대상이었던 결함
    /// ("레전더리는 절대 레전더리를 못 준다")을 직접 잠근다.
    func testLegendaryGradeOnlyPicksLegendaryOrMythicalCandidates() {
        let index = [
            BaseSpecies(id: 1, captureRate: 255, isLegendary: false, isMythical: false),   // 최흔 커먼
            BaseSpecies(id: 2, captureRate: 45, isLegendary: false, isMythical: false),    // 에픽
            BaseSpecies(id: 3, captureRate: 3, isLegendary: true, isMythical: false),      // 레전더리
            BaseSpecies(id: 4, captureRate: 3, isLegendary: false, isMythical: true),      // 미시컬(→레전더리 취급)
        ]
        for step in stride(from: 0.0, through: 1.0, by: 0.1) {
            let chosen = EggBalance.pickSpecies(from: index, grade: .legendary, roll: step)
            XCTAssertTrue([3, 4].contains(chosen), "roll \(step) → \(chosen) 은 전설/미시컬이 아님")
        }
    }

    /// **레전더리 풀은 포획률을 안 본다.** 이 등급만 포획률이 아니라 플래그로 정해져, 풀에
    /// 3부터 255까지 섞여 들어온다. 그 255 는 원작에서 스토리상 반드시 잡게 되는 아이라 붙은
    /// 값이지 흔하다는 뜻이 아니다(테라파고스·무한다이노·네크로즈마). 포획률로 가중하던 시절엔
    /// 이 셋이 레전더리 알의 56% 를 차지하고 뮤츠는 0.22% 였다 — 85배 차이.
    func testLegendaryCandidatesAreEquallyLikelyRegardlessOfCaptureRate() {
        let index = [
            BaseSpecies(id: 1, captureRate: 3, isLegendary: true, isMythical: false),    // 뮤츠 부류
            BaseSpecies(id: 2, captureRate: 255, isLegendary: true, isMythical: false),  // 테라파고스 부류
            BaseSpecies(id: 3, captureRate: 45, isLegendary: false, isMythical: true),   // 뮤 부류
        ]
        var counts: [Int: Int] = [:]
        let samples = 3000
        for i in 0..<samples {
            counts[EggBalance.pickSpecies(from: index, grade: .legendary,
                                          roll: Double(i) / Double(samples)), default: 0] += 1
        }
        let expected = samples / index.count
        for id in [1, 2, 3] {
            XCTAssertEqual(counts[id] ?? 0, expected, accuracy: 2,
                           "#\(id) 이 균등하지 않다 — \(counts)")
        }
    }

    /// **아래 등급으로 내려갔으면 그 등급의 가중 방식을 쓴다.** 레전더리 요청이 비어 에픽으로
    /// 떨어졌는데도 균등을 적용하면, 포획률이 뜻을 갖는 풀에서 그 정보를 잃는다.
    func testFallingBackFromLegendaryStillWeightsTheLowerGrade() {
        let index = [
            BaseSpecies(id: 1, captureRate: 3, isLegendary: false, isMythical: false),   // 에픽, 희귀
            BaseSpecies(id: 2, captureRate: 45, isLegendary: false, isMythical: false),  // 에픽, 흔함
        ]
        var counts: [Int: Int] = [1: 0, 2: 0]
        let samples = 480
        for i in 0..<samples {
            counts[EggBalance.pickSpecies(from: index, grade: .legendary,
                                          roll: Double(i) / Double(samples)), default: 0] += 1
        }
        XCTAssertGreaterThan(counts[2] ?? 0, (counts[1] ?? 0) * 10,
                             "에픽으로 내려갔는데 포획률 가중이 사라졌다 — \(counts)")
    }

    /// 포획률이 낮을수록(=더 흔함) 가중이 커진다. 첫 후보·마지막 후보 모두 어떤 굴림으로도 뽑혀야
    /// 한다(경계에서 누락되면 그 종은 영원히 안 나온다). 두 후보 모두 커먼 등급(포획률 >120)이라
    /// 등급 필터를 그대로 통과하고 가중치 차이만 순수하게 본다.
    func testWeightingFavorsHigherCaptureRateWithoutStrandingEnds() {
        let index = [
            BaseSpecies(id: 1, captureRate: 130, isLegendary: false, isMythical: false),
            BaseSpecies(id: 2, captureRate: 255, isLegendary: false, isMythical: false),
        ]
        var counts: [Int: Int] = [1: 0, 2: 0]
        let samples = 200
        for i in 0..<samples {
            let roll = Double(i) / Double(samples)
            let chosen = EggBalance.pickSpecies(from: index, grade: .common, roll: roll)
            counts[chosen, default: 0] += 1
        }
        XCTAssertGreaterThan(counts[2] ?? 0, counts[1] ?? 0,
                             "포획률 255 종이 포획률 130 종보다 더 자주 나와야 한다")
        // 양 끝(roll=0, roll 최댓값 부근)에서도 두 후보 모두 도달 가능해야 한다.
        XCTAssertEqual(EggBalance.pickSpecies(from: index, grade: .common, roll: 0.0), 1,
                       "roll 0 은 항상 첫 후보")
        XCTAssertEqual(EggBalance.pickSpecies(from: index, grade: .common, roll: 0.999999), 2,
                       "roll 이 1에 가까우면 마지막 후보에 도달해야 한다")
        XCTAssertEqual(EggBalance.pickSpecies(from: index, grade: .common, roll: 1.0), 2,
                       "roll == 1.0 경계에서도 범위를 벗어나지 않고 마지막 후보를 가리켜야 한다")
    }

    /// 요청 등급의 후보가 비어 있으면 전체 인덱스로 넓히지 않고 한 단계 아래 등급으로 내려간다 —
    /// 그러지 않으면 포획률 가중이 가장 흔한 종을 편애해 "레전더리 뽑기가 최흔 종을 준다"는
    /// 정확히 그 결함이 재발한다.
    func testEmptyGradePoolFallsBackOneGradeDownNotToWholeIndex() {
        // 레전더리 후보 없음. 에픽 후보 하나, 커먼(최흔) 후보 하나 — 레전더리를 굴려도
        // 커먼이 아니라 한 단계 아래인 에픽에서 골라야 한다.
        let index = [
            BaseSpecies(id: 1, captureRate: 255, isLegendary: false, isMythical: false),   // 커먼
            BaseSpecies(id: 2, captureRate: 45, isLegendary: false, isMythical: false),    // 에픽
        ]
        let chosen = EggBalance.pickSpecies(from: index, grade: .legendary, roll: 0.5)
        XCTAssertEqual(chosen, 2, "레전더리 후보가 없으면 커먼(전체)이 아니라 한 단계 아래(에픽)에서 골라야 한다")
    }

    /// 요청 등급이 이미 최하단(커먼)이고 그마저 후보가 없으면 더 내려갈 데가 없다 — 크래시하지
    /// 않고 전체 인덱스를 최후의 보루로 쓴다(인덱스 자체는 비어있지 않다고 보장되므로 발생 자체가
    /// 극히 드물지만, 안전망은 여전히 있어야 한다).
    func testFallsBackToWholeIndexOnlyWhenCommonPoolIsEmpty() {
        // 전부 레어 등급(포획률 46~120)만 있는 인덱스 — 커먼 등급 후보가 아예 없다.
        let index = [
            BaseSpecies(id: 9, captureRate: 100, isLegendary: false, isMythical: false),
        ]
        let chosen = EggBalance.pickSpecies(from: index, grade: .common, roll: 0.5)
        XCTAssertEqual(chosen, 9)
    }

    /// **레지기가스(486)는 알에서 안 나온다 — 어떤 굴림에도.** 레지 패밀리 완성 보상이
    /// 유일한 입수처라는 약속이고, `pickSpecies` 가 종 선택의 유일한 관문이라(뽑기·확정권·
    /// 박사의 제안) 여기 하나로 전 경로가 잠긴다.
    func testRewardOnlySpeciesNeverComeFromAnyRoll() {
        let index = [
            BaseSpecies(id: 486, captureRate: 3, isLegendary: true, isMythical: false),
            BaseSpecies(id: 150, captureRate: 3, isLegendary: true, isMythical: false),
        ]
        for roll in stride(from: 0.0, through: 1.0, by: 0.01) {
            XCTAssertEqual(EggBalance.pickSpecies(from: index, grade: .legendary, roll: roll),
                           150, "굴림 \(roll) 에서 보상 전용 종이 알로 나왔다")
        }
    }

    /// 풀에 보상 전용 종만 남으면 그 등급은 **빈 것으로 취급**된다 — 등급 걷기가 아래로
    /// 내려간다(빈 풀 규칙 그대로). 제외를 등급 걷기 *뒤에* 하면 후보 0 으로 크래시하는 부류다.
    func testAGradeMadeOfRewardOnlySpeciesCountsAsEmpty() {
        let index = [
            BaseSpecies(id: 486, captureRate: 3, isLegendary: true, isMythical: false),  // 유일한 레전더리
            BaseSpecies(id: 2, captureRate: 45, isLegendary: false, isMythical: false),  // 에픽
        ]
        let chosen = EggBalance.pickSpecies(from: index, grade: .legendary, roll: 0.5)
        XCTAssertEqual(chosen, 2, "보상 전용 종뿐인 등급은 한 단계 아래로 내려가야 한다")
    }
}

final class EggTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func egg(hatchesIn seconds: TimeInterval) -> Egg {
        Egg(grade: .common, speciesID: 1, shiny: false,
            startedAt: now, hatchesAt: now.addingTimeInterval(seconds))
    }

    func testReadyOnlyAfterHatchTime() {
        XCTAssertFalse(egg(hatchesIn: 10).isReady(at: now))
        XCTAssertTrue(egg(hatchesIn: 10).isReady(at: now.addingTimeInterval(10)))
        XCTAssertTrue(egg(hatchesIn: 10).isReady(at: now.addingTimeInterval(999)))
    }

    func testRemainingNeverNegative() {
        XCTAssertEqual(egg(hatchesIn: 60).remaining(at: now), 60, accuracy: 0.001)
        XCTAssertEqual(egg(hatchesIn: 60).remaining(at: now.addingTimeInterval(999)), 0)
    }
}

/// 도감에 없는 종 밀어주기 — 박사의 제안만 쓴다.
final class UnseenBoostTests: XCTestCase {
    private func index() -> [BaseSpecies] {
        // 전부 커먼(포획률 >120)이고 값이 같아, 가중 차이는 도감 여부에서만 온다.
        (1...4).map { BaseSpecies(id: $0, captureRate: 200, isLegendary: false, isMythical: false) }
    }

    /// **`unseenIn` 을 안 주면 알 뽑기의 분포가 한 비트도 안 바뀐다.** 알은 무엇이 나올지
    /// 모르고 사는 것이라 도감을 봐 주면 성격이 달라진다.
    func testOmittingTheDexLeavesTheDistributionUntouched() {
        for i in 0..<400 {
            let roll = Double(i) / 400
            XCTAssertEqual(EggBalance.pickSpecies(from: index(), grade: .common, roll: roll),
                           EggBalance.pickSpecies(from: index(), grade: .common, roll: roll,
                                                  unseenIn: nil),
                           "roll \(roll)")
        }
    }

    /// 미보유 종이 보유 종보다 자주 나온다 — 배수만큼.
    func testUnseenSpeciesComeUpMoreOften() {
        var counts: [Int: Int] = [:]
        let samples = 2000
        for i in 0..<samples {
            let chosen = EggBalance.pickSpecies(from: index(), grade: .common,
                                                roll: Double(i) / Double(samples),
                                                unseenIn: [1, 2])   // 3·4 가 미보유
            counts[chosen, default: 0] += 1
        }
        let seen = (counts[1] ?? 0) + (counts[2] ?? 0)
        let unseen = (counts[3] ?? 0) + (counts[4] ?? 0)
        // 같은 포획률 2:2 이므로 미보유 쪽이 정확히 `unseenBoost` 배.
        XCTAssertEqual(Double(unseen) / Double(seen), Double(EggBalance.unseenBoost),
                       accuracy: 0.05, "seen \(seen) unseen \(unseen)")
    }

    /// **그 등급을 다 모았으면 분포가 원래대로 돌아온다** — 모두가 같은 배수를 받으므로.
    /// 인덱스를 미리 걸러 넘겼다면 여기서 등급이 아래로 내려갔을 자리다.
    func testAFullyCollectedGradeFallsBackToTheNormalDistribution() {
        let all: Set<Int> = [1, 2, 3, 4]
        for i in 0..<400 {
            let roll = Double(i) / 400
            XCTAssertEqual(EggBalance.pickSpecies(from: index(), grade: .common, roll: roll,
                                                  unseenIn: all),
                           EggBalance.pickSpecies(from: index(), grade: .common, roll: roll),
                           "roll \(roll)")
        }
    }

    /// 배수는 "살짝" 이다 — 1 이면 기능이 없는 것이고, 너무 크면 우선이 아니라 확정이 된다.
    func testTheBoostIsModest() {
        XCTAssertGreaterThan(EggBalance.unseenBoost, 1)
        XCTAssertLessThanOrEqual(EggBalance.unseenBoost, 4)
    }
}
