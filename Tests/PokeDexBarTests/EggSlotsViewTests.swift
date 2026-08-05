import AppKit
import SwiftUI
import XCTest
@testable import PokeDexBar

final class EggSlotsViewTests: XCTestCase {
    /// 한국어 표기 — 단위는 큰 것 두 개까지만.
    func testCountdownFormatsKorean() {
        XCTAssertEqual(EggSlotsView.countdownText(0, .ko), "부화!")
        XCTAssertEqual(EggSlotsView.countdownText(45, .ko), "45초")
        XCTAssertEqual(EggSlotsView.countdownText(90, .ko), "1분 30초")
        XCTAssertEqual(EggSlotsView.countdownText(3 * 3600 + 12 * 60, .ko), "3시간 12분")
        XCTAssertEqual(EggSlotsView.countdownText(25 * 3600, .ko), "1일 1시간")
    }

    func testCountdownFormatsEnglish() {
        XCTAssertEqual(EggSlotsView.countdownText(0, .en), "Hatched!")
        XCTAssertEqual(EggSlotsView.countdownText(45, .en), "45s")
        XCTAssertEqual(EggSlotsView.countdownText(90, .en), "1m 30s")
        XCTAssertEqual(EggSlotsView.countdownText(3 * 3600 + 12 * 60, .en), "3h 12m")
        XCTAssertEqual(EggSlotsView.countdownText(25 * 3600, .en), "1d 1h")
    }

    func testCountdownFormatsJapanese() {
        XCTAssertEqual(EggSlotsView.countdownText(0, .ja), "ふ化!")
        XCTAssertEqual(EggSlotsView.countdownText(45, .ja), "45秒")
        XCTAssertEqual(EggSlotsView.countdownText(90, .ja), "1分30秒")
        XCTAssertEqual(EggSlotsView.countdownText(3 * 3600 + 12 * 60, .ja), "3時間12分")
        XCTAssertEqual(EggSlotsView.countdownText(25 * 3600, .ja), "1日1時間")
    }

    /// 남은 시간이 음수로 들어와도(시계 되감김) 부화로 표시한다.
    func testNegativeRemainingIsReady() {
        XCTAssertEqual(EggSlotsView.countdownText(-10, .ko), "부화!")
    }

    /// 0.9초처럼 1초 미만이 남았어도 진짜로 부화한 게 아니면 "부화!"를 미리 말하지 않는다
    /// (올림 처리 — 잘라내면 최대 1초 일찍 표시된다).
    func testSubSecondRemainingIsNotYetReady() {
        XCTAssertNotEqual(EggSlotsView.countdownText(0.9, .ko), "부화!")
        XCTAssertEqual(EggSlotsView.countdownText(0.9, .ko), "1초")
    }

    /// 슬롯 최대치(`EggBalance.maxSlots`)까지 한 줄로 늘어놓으면 팝오버 콘텐츠 폭을 넘는다 —
    /// 그래서 `EggSlotsView` 가 이 줄을 가로 `ScrollView` 로 감싼다(잘리지 않고 스크롤).
    /// 타일 크기를 바꿔 이 부등식이 깨지면(=더 이상 안 넘치면) 스크롤 감싸기가 여전히 필요한지
    /// 다시 판단해야 한다는 신호다.
    func testMaxSlotsRowOverflowsContentWidth() {
        let width = EggSlotsView.rowWidth(forSlotCount: EggBalance.maxSlots)
        XCTAssertGreaterThan(width, PopoverMetrics.contentWidth)
    }

    /// 알이 없으면 1초 틱을 걸지 않는다 — 알을 한 번도 안 뽑은 사용자에게 매초 재렌더는 순손실이다.
    func testCountdownTickOnlyWhenAnEggIsHatching() {
        var state = PlayerState()
        XCTAssertFalse(PopoverView.needsCountdownTick(state))
        state.eggs = [Egg(grade: .common, speciesID: 1, shiny: false,
                          startedAt: Date(timeIntervalSince1970: 0),
                          hatchesAt: Date(timeIntervalSince1970: 1800))]
        XCTAssertTrue(PopoverView.needsCountdownTick(state))
    }
}

/// 팝오버를 열어 둔 채 부화 시각이 지나면 그 자리에서 깨야 한다. 카운트다운 틱에 정산이 안 붙어
/// 있으면 타일이 "부화!"에 멈춘 채 다음 사용량 새로고침까지(수동 프리셋이면 무한정) 그대로였다.
/// 스토어의 `settleHatches` 를 직접 부르는 테스트는 이 배선이 없어도 통과하므로, 뷰를 호스팅해
/// **틱이 지나가는 것만으로** 정산되는지를 잰다(rootView 교체 = 1초 틱 한 번).
@MainActor
final class EggSlotsTickSettleTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore() -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("egg-tick-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1), now: { self.start })
        store.seedForTesting(wallet: 0, slots: 3, eggs: 1, at: start)
        return store
    }

    func testTickPastHatchTimeSettlesTheEgg() {
        let store = makeStore()
        let host = NSHostingView(rootView: EggSlotsView(store: store, now: start))
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(store.state.eggs.count, 1, "아직 부화 시각 전이다")

        // 다음 틱 — 부화 시각을 지난 시각이 들어온다.
        host.rootView = EggSlotsView(store: store, now: start.addingTimeInterval(EggBalance.duration(.common)))
        host.layoutSubtreeIfNeeded()
        XCTAssertTrue(store.state.eggs.isEmpty, "틱이 부화 시각을 지났는데 알이 슬롯에 남아 있다")
        XCTAssertEqual(store.state.box.count, 1, "부화한 개체가 박스에 들어와야 한다")
    }

    /// 익지 않은 알은 틱마다 건드리지 않는다 — 틱은 초당 한 번 도는 경로라 헛일을 하면 안 된다.
    func testTickBeforeHatchTimeLeavesTheEggAlone() {
        let store = makeStore()
        let host = NSHostingView(rootView: EggSlotsView(store: store, now: start))
        host.layoutSubtreeIfNeeded()
        host.rootView = EggSlotsView(store: store, now: start.addingTimeInterval(60))
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(store.state.eggs.count, 1)
        XCTAssertTrue(store.state.box.isEmpty)
    }
}
