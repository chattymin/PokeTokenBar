import XCTest
@testable import PokeDexBar

/// 레벨 이전 세이브가 올라올 때 무엇이 살아남나.
final class LevelMigrationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func decode(_ json: String) throws -> Individual {
        try JSONDecoder().decode(Individual.self, from: Data(json.utf8))
    }

    /// **구 세이브에는 두 필드가 없다.** 없다고 개체를 버리면 박스가 통째로 사라진다.
    func testAnOldIndividualStillDecodes() throws {
        let json = """
        {"id":"\(UUID().uuidString)","baseID":4,"speciesID":4,"pathIDs":[4],
         "nature":"hardy","obtainedAt":0,"grade":"common","exp":250000000}
        """
        let individual = try decode(json)
        XCTAssertEqual(individual.speciesID, 4)
        XCTAssertEqual(individual.growthRate, .mediumFast, "성장 타입 기본값이 안 들어갔다")
    }

    /// **알 진행분은 안 뺏는다.** 구 세이브의 `exp` 는 알 계량기이기도 했다.
    func testAnOldSaveKeepsItsEggProgress() throws {
        let json = """
        {"id":"\(UUID().uuidString)","baseID":4,"speciesID":4,"pathIDs":[4],
         "nature":"hardy","obtainedAt":0,"grade":"common","exp":250000000}
        """
        XCTAssertEqual(try decode(json).eggProgress, 250_000_000)
    }

    /// **경험치는 토큰에서 EXP 로 환산된다.** 2.5억 토큰 ÷ 500 = 50만 EXP → mediumFast L79.
    func testAnOldSaveConvertsTokensToExperience() throws {
        let json = """
        {"id":"\(UUID().uuidString)","baseID":4,"speciesID":4,"pathIDs":[4],
         "nature":"hardy","obtainedAt":0,"grade":"common","exp":250000000}
        """
        let individual = try decode(json)
        XCTAssertEqual(individual.exp, 500_000)
        XCTAssertEqual(individual.level, GrowthRate.mediumFast.level(forExp: 500_000))
        XCTAssertEqual(individual.level, 79)
    }

    /// **새 세이브는 환산하지 않는다.** `eggProgress` 키가 있으면 이미 이전이 끝난 것이다 —
    /// 대조군이 없으면 "매번 500으로 나누는" 구현도 위 테스트를 통과한다.
    func testANewSaveIsNotConvertedAgain() throws {
        let json = """
        {"id":"\(UUID().uuidString)","baseID":4,"speciesID":4,"pathIDs":[4],
         "nature":"hardy","obtainedAt":0,"grade":"common","exp":500000,"eggProgress":250000000,
         "growthRate":"mediumSlow"}
        """
        let individual = try decode(json)
        XCTAssertEqual(individual.exp, 500_000, "이미 EXP 인 값을 또 나눴다")
        XCTAssertEqual(individual.eggProgress, 250_000_000)
        XCTAssertEqual(individual.growthRate, .mediumSlow)
    }

    /// 값 범위 검증 — 관대 디코딩의 짝. 산술에 쓰이는 수치라 경계에서 자른다.
    func testAbsurdValuesAreClamped() throws {
        let json = """
        {"id":"\(UUID().uuidString)","baseID":4,"speciesID":4,"pathIDs":[4],
         "nature":"hardy","obtainedAt":0,"grade":"common",
         "exp":9223372036854775807,"eggProgress":9223372036854775807,"growthRate":"slow"}
        """
        let individual = try decode(json).sanitized()
        XCTAssertEqual(individual.exp, GrowthRate.slow.totalExp(at: 100))
        XCTAssertEqual(individual.eggProgress, ExpBalance.eggThreshold(grade: .common))

        let negative = """
        {"id":"\(UUID().uuidString)","baseID":4,"speciesID":4,"pathIDs":[4],
         "nature":"hardy","obtainedAt":0,"grade":"common","exp":-5,"eggProgress":-5}
        """
        let fixed = try decode(negative).sanitized()
        XCTAssertEqual(fixed.exp, 0)
        XCTAssertEqual(fixed.eggProgress, 0)
    }

    /// 레벨은 성장 타입을 따른다 — 같은 경험치라도 타입이 다르면 레벨이 다르다.
    func testLevelFollowsTheGrowthRate() {
        func make(_ rate: GrowthRate) -> Individual {
            Individual(baseID: 1, speciesID: 1, pathIDs: [1], nature: .hardy, exp: 600_000,
                       obtainedAt: now, grade: .common, growthRate: rate)
        }
        XCTAssertEqual(make(.erratic).level, 100)
        // slow: totalExp(78)=593,190 <= 600,000 < totalExp(79)=616,298 → L78 (검증: GrowthRateTests).
        XCTAssertEqual(make(.slow).level, 78)
        XCTAssertNotEqual(make(.erratic).level, make(.slow).level)
    }
}
