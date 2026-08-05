import AppKit
import SwiftUI
import XCTest
@testable import PokeDexBar

final class NationalDexTests: XCTestCase {
    /// 전국도감은 1번부터 마지막 종까지 빠짐없이 칸을 만든다 — 희귀도로 나누지 않는다.
    func testRangeCoversEverySpecies() {
        XCTAssertEqual(NationalDexView.speciesRange, 1...1025)
        XCTAssertEqual(NationalDexView.speciesRange.count, 1025)
    }

    /// 모든 칸이 스프라이트를 그릴 수 있어야 한다(실루엣도 스프라이트가 있어야 만든다).
    func testEverySlotHasASlug() {
        for id in NationalDexView.speciesRange {
            XCTAssertNotNil(SpeciesSlug.slug(id), "종 \(id) 슬러그 없음")
        }
    }

    func testProgressText() {
        XCTAssertEqual(NationalDexView.progressText(caught: 0), "0 / 1025")
        XCTAssertEqual(NationalDexView.progressText(caught: 142), "142 / 1025")
    }
}

@MainActor
final class NationalDexRenderTests: XCTestCase {
    /// 1025칸이 있어도 뷰 조립이 즉시 끝나야 한다 — 전부 미리 만들면 팝오버가 멈춘다.
    func testGridAssemblesQuickly() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dex-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1),
                                now: { Date(timeIntervalSince1970: 0) })
        let started = ProcessInfo.processInfo.systemUptime
        let host = NSHostingView(rootView: NationalDexView(store: store)
            .frame(width: PopoverMetrics.width))
        host.layoutSubtreeIfNeeded()
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        XCTAssertLessThan(elapsed, 2.0, "도감 그리드 조립이 \(elapsed)초 걸렸다 — 지연 로드가 안 걸렸다")
    }
}
