import XCTest
import SwiftUI
@testable import PokeDexBar

@MainActor
final class LevelViewTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func made(_ level: Int, plus: Int = 0) -> Individual {
        Individual(baseID: 4, speciesID: 4, pathIDs: [4], nature: .hardy,
                   exp: GrowthRate.mediumFast.totalExp(at: level) + plus,
                   obtainedAt: now, grade: .common, growthRate: .mediumFast)
    }

    /// 다음 레벨까지 남은 EXP — 딱 도달한 순간에는 그 레벨 구간 전체가 남는다.
    func testExpToNextLevel() {
        let l50 = made(50)
        let span = GrowthRate.mediumFast.totalExp(at: 51) - GrowthRate.mediumFast.totalExp(at: 50)
        XCTAssertEqual(IndividualDetailView.expToNext(l50), span)
        XCTAssertEqual(IndividualDetailView.expToNext(made(50, plus: span - 1)), 1)
    }

    /// 100레벨은 다음이 없다 — 남은 값이 0이고 진행도가 가득이다.
    func testMaxLevelHasNothingLeft() {
        XCTAssertEqual(IndividualDetailView.expToNext(made(100)), 0)
        XCTAssertEqual(IndividualDetailView.levelProgress(made(100)), 1, accuracy: 1e-9)
    }

    /// 진행도는 그 레벨 구간 안의 비율이다 — 레벨이 오른 직후엔 0에 가깝다.
    func testProgressIsWithinTheCurrentLevel() {
        XCTAssertEqual(IndividualDetailView.levelProgress(made(50)), 0, accuracy: 1e-9)
        let span = GrowthRate.mediumFast.totalExp(at: 51) - GrowthRate.mediumFast.totalExp(at: 50)
        XCTAssertEqual(IndividualDetailView.levelProgress(made(50, plus: span / 2)),
                       0.5, accuracy: 0.01)
    }

    /// 문구가 세 언어를 다 채운다.
    func testLevelStringsCoverAllThreeLanguages() {
        for lang in AppLanguage.allCases {
            XCTAssertFalse(L(lang).levelLabel(47).isEmpty, "\(lang)")
            XCTAssertFalse(L(lang).expToNextLevel("8,240").isEmpty, "\(lang)")
            XCTAssertFalse(L(lang).eggProgressLabel.isEmpty, "\(lang)")
        }
        XCTAssertTrue(L(.en).levelLabel(47).contains("47"))
    }

    /// **화면이 실제로 레벨을 그린다.** 순수 함수가 다 맞아도 뷰가 안 쓰면 아무 일도 안 난다.
    func testTheDetailViewRendersTheLevel() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "Sources/PokeDexBar/UI/IndividualDetailView.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("levelLabel"), "상세에 레벨 문구가 없다")
        XCTAssertTrue(source.contains("eggProgress"), "상세에 알 진행이 없다")
        XCTAssertFalse(source.contains("ExpBalance.threshold("), "옛 진화 임계가 남아 있다")
    }
}
