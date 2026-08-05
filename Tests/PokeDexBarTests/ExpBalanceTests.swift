import XCTest
@testable import PokeDexBar

final class ExpBalanceTests: XCTestCase {
    /// 스펙 표 그대로 — 1→2단계는 등급별 기본값, 2→3단계는 그 3배.
    func testThresholdTable() {
        XCTAssertEqual(ExpBalance.threshold(grade: .common, stageIndex: 0), 50_000_000)
        XCTAssertEqual(ExpBalance.threshold(grade: .common, stageIndex: 1), 150_000_000)
        XCTAssertEqual(ExpBalance.threshold(grade: .rare, stageIndex: 0), 100_000_000)
        XCTAssertEqual(ExpBalance.threshold(grade: .rare, stageIndex: 1), 300_000_000)
        XCTAssertEqual(ExpBalance.threshold(grade: .epic, stageIndex: 0), 200_000_000)
        XCTAssertEqual(ExpBalance.threshold(grade: .epic, stageIndex: 1), 600_000_000)
        XCTAssertEqual(ExpBalance.threshold(grade: .legendary, stageIndex: 0), 400_000_000)
        XCTAssertEqual(ExpBalance.threshold(grade: .legendary, stageIndex: 1), 1_200_000_000)
    }

    /// 등급이 높을수록 오래 걸린다 — 순서가 뒤집히면 밸런스가 무너진다.
    func testHigherGradeCostsMore() {
        for stage in 0...1 {
            let common = ExpBalance.threshold(grade: .common, stageIndex: stage)
            let rare = ExpBalance.threshold(grade: .rare, stageIndex: stage)
            let epic = ExpBalance.threshold(grade: .epic, stageIndex: stage)
            let legendary = ExpBalance.threshold(grade: .legendary, stageIndex: stage)
            XCTAssertLessThan(common, rare)
            XCTAssertLessThan(rare, epic)
            XCTAssertLessThan(epic, legendary)
        }
    }

    /// 3형태를 넘는 경로(비정상)에서도 2→3 임계로 수렴하고 0이나 음수가 되지 않는다.
    func testDeepStagesStayPositive() {
        XCTAssertGreaterThan(ExpBalance.threshold(grade: .common, stageIndex: 5), 0)
    }
}

final class StarterCatalogTests: XCTestCase {
    func testNineGenerationsOfThree() {
        XCTAssertEqual(StarterCatalog.byGeneration.count, 9)
        XCTAssertEqual(StarterCatalog.all.count, 27)
        for entry in StarterCatalog.byGeneration {
            XCTAssertEqual(entry.speciesIDs.count, 3, "\(entry.generation)세대 스타터가 3마리가 아니다")
        }
    }

    func testKnownStarters() {
        XCTAssertEqual(StarterCatalog.byGeneration.first?.speciesIDs, [1, 4, 7])
        XCTAssertEqual(StarterCatalog.byGeneration.last?.speciesIDs, [906, 909, 912])
        XCTAssertTrue(StarterCatalog.contains(495))
        XCTAssertFalse(StarterCatalog.contains(25))
    }

    /// 스타터는 전부 스프라이트를 그릴 수 있어야 한다 — 못 그리는 칸이 선택지에 있으면 안 된다.
    func testEveryStarterHasASprite() {
        for id in StarterCatalog.all {
            XCTAssertNotNil(SpeciesSlug.slug(id), "종 \(id) 슬러그 없음")
        }
    }
}
