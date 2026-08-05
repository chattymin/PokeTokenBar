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
    /// 1025칸을 전부 만들면 스프라이트 요청이 그만큼 나가 팝오버가 멈춘다 — `LazyVGrid` 가 화면에
    /// 들어온 칸만 만드는지 벽시계가 아니라 실제 생성 개수로 잰다(벽시계는 스프라이트 fetch 가
    /// 비동기·렌더 스레드 밖이라 eager 하게 1025개를 다 만들어도 통과해버려 못 걸렀다).
    func testGridBuildsOnlyVisibleCells() {
        SpriteView.resetConstructionCount()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dex-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1),
                                now: { Date(timeIntervalSince1970: 0) })
        let host = NSHostingView(rootView: NationalDexView(store: store)
            .frame(width: PopoverMetrics.width))
        host.layoutSubtreeIfNeeded()
        // 뷰포트 크기·플랫폼 차이를 허용하는 여유(200)를 두되, 전체 1025개와는 확실히 구분되는 상한.
        XCTAssertLessThan(SpriteView.constructionCount, 200,
            "SpriteView 가 \(SpriteView.constructionCount)개 만들어짐 — 지연 로드가 안 걸렸다")
    }
}
