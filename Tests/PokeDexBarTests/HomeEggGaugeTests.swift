import XCTest
import SwiftUI
@testable import PokeDexBar

/// 홈 파트너 카드의 알 게이지.
@MainActor
final class HomeEggGaugeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore() -> PlayerStore {
        PlayerStore(fileURL: FileManager.default.temporaryDirectory
                        .appendingPathComponent("gauge-\(UUID().uuidString).json"),
                    rng: SeededRNG(seed: 1), now: { self.now },
                    defaults: UserDefaults(suiteName: UUID().uuidString)!)
    }

    /// **꽉 찬 것만으로는 안 흔든다.** 빈 슬롯이 없으면 눌러도 아무 일이 안 나는데 흔들어
    /// 부르는 건 거짓말이다. 네 조합을 전수로 잠근다 — 한 조합만 보면 "항상 흔든다"도 통과한다.
    func testItShakesOnlyWhenTappingWouldActuallyWork() {
        XCTAssertTrue(HomeEggGauge.shouldShake(full: true, hasFreeSlot: true))
        XCTAssertFalse(HomeEggGauge.shouldShake(full: true, hasFreeSlot: false), "슬롯이 없는데 흔든다")
        XCTAssertFalse(HomeEggGauge.shouldShake(full: false, hasFreeSlot: true), "덜 찼는데 흔든다")
        XCTAssertFalse(HomeEggGauge.shouldShake(full: false, hasFreeSlot: false))
    }

    /// 채움 높이는 아래에서부터 비율만큼. 범위 밖 값이 와도 알 밖으로 안 나간다.
    func testFilledHeightStaysInsideTheEgg() {
        XCTAssertEqual(HomeEggGauge.filledHeight(progress: 0, size: 22), 0, accuracy: 1e-9)
        XCTAssertEqual(HomeEggGauge.filledHeight(progress: 0.5, size: 22), 11, accuracy: 1e-9)
        XCTAssertEqual(HomeEggGauge.filledHeight(progress: 1, size: 22), 22, accuracy: 1e-9)
        XCTAssertEqual(HomeEggGauge.filledHeight(progress: 3, size: 22), 22, accuracy: 1e-9)
        XCTAssertEqual(HomeEggGauge.filledHeight(progress: -1, size: 22), 0, accuracy: 1e-9)
        XCTAssertEqual(HomeEggGauge.filledHeight(progress: .nan, size: 22), 0, accuracy: 1e-9)
    }

    /// **게이지는 상세 화면과 같은 계산을 쓴다.** 두 화면이 같은 알을 다른 퍼센트로 그리면 안 된다.
    func testItUsesTheSameProgressAsTheDetailScreen() {
        var individual = Individual(baseID: 4, speciesID: 4, pathIDs: [4], nature: .hardy,
                                    obtainedAt: now, grade: .rare)
        individual.eggProgress = ExpBalance.eggThreshold(grade: .rare) / 4
        XCTAssertEqual(IndividualDetailView.eggProgress(individual), 0.25, accuracy: 1e-9)
    }

    /// **누르면 실제로 알을 받는다.** 순수 함수가 다 맞아도 배선이 끊기면 아무 일도 안 난다 —
    /// 이 레포가 반복해서 겪은 결함 부류라 홈을 실제로 그려서 기록된 동작을 직접 부른다.
    func testTappingTheGaugeTakesTheEgg() {
        let store = makeStore()
        store.seedForTesting(wallet: 0, slots: 3, eggs: 0, at: now)
        var partner = Individual(baseID: 4, speciesID: 4, pathIDs: [4], nature: .hardy,
                                 obtainedAt: now, grade: .common)
        partner.eggProgress = ExpBalance.eggThreshold(grade: .common)
        store.mutate { $0.box = [partner]; $0.partnerID = partner.id }
        let line = EvoLine(baseID: 4, tree: EvoNode(speciesID: 4, children: []),
                           rarity: .common, names: [:])

        HomeEggGauge.resetConstructed()
        let gauge = HomeEggGauge(grade: partner.grade,
                                 progress: IndividualDetailView.eggProgress(partner),
                                 shaking: true) {
            store.takeFoundEgg(individualID: partner.id, line: line)
        }
        let host = NSHostingView(rootView: AnyView(gauge))
        host.layoutSubtreeIfNeeded()

        guard let recorded = HomeEggGauge.constructed.last else {
            return XCTFail("게이지가 안 그려졌다")
        }
        XCTAssertEqual(recorded.progress, 1, accuracy: 1e-9)
        XCTAssertTrue(recorded.shaking)
        recorded.action()

        XCTAssertEqual(store.state.eggs.count, 1, "눌렀는데 알이 안 들어왔다")
        XCTAssertEqual(store.state.box.first?.eggProgress, 0, "게이지가 안 비워졌다")
    }

    /// **홈이 실제로 게이지를 만든다.** 뷰를 만들어 놓고 화면에 안 걸면 아무도 못 본다.
    func testTheHomeScreenWiresTheGauge() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "Sources/PokeDexBar/UI/PopoverView.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("HomeEggGauge("), "홈이 게이지를 안 만든다")
        XCTAssertTrue(source.contains("takeFoundEgg"), "게이지가 받는 경로에 안 닿는다")
    }
}
