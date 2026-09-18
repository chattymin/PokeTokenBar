import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor
final class LimitProgressRenderingTests: XCTestCase {
    func testRemainingModeReversesRenderedFillAndClampsExhaustedQuota() throws {
        let suite = "LimitProgressRendering-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UsageStore(providers: [], autoRefresh: false, defaults: defaults)

        func renderedPercent(_ used: Double) throws -> Double {
            let view = LimitProgressBar(usedPercent: used, tint: .blue)
                .environment(store).frame(width: 240, height: 20)
            let host = NSHostingController(rootView: view)
            host.view.frame = NSRect(x: 0, y: 0, width: 240, height: 20)
            host.view.layoutSubtreeIfNeeded()
            func descendants(_ view: NSView) -> [NSView] {
                [view] + view.subviews.flatMap(descendants)
            }
            let views = descendants(host.view)
            let bar = try XCTUnwrap(views.compactMap { $0 as? NSProgressIndicator }.first,
                                   views.map { String(describing: type(of: $0)) }.joined(separator: ","))
            return bar.doubleValue / bar.maxValue * 100
        }

        store.limitDisplayMode = .used
        XCTAssertEqual(try renderedPercent(25), 25, accuracy: 0.01)
        store.limitDisplayMode = .remaining
        XCTAssertEqual(try renderedPercent(25), 75, accuracy: 0.01)
        XCTAssertEqual(try renderedPercent(125), 0, accuracy: 0.01)
        XCTAssertEqual(try renderedPercent(0), 100, accuracy: 0.01)
        store.limitDisplayMode = .used
        XCTAssertEqual(try renderedPercent(25), 25, accuracy: 0.01)
    }

    /// 페이스 눈금은 SwiftUI 도형이라 NSView 로 내려오지 않는다 → 실제로 칠해진 픽셀을 본다.
    /// 위치 계산만 순수 함수로 검증하면 "뷰가 그 함수를 정말 `limitDisplayMode` 로 호출하는가"는
    /// 무검증으로 남고, 채움만 뒤집히고 눈금은 그대로였던 #286 부류가 그 틈으로 다시 들어온다.
    func testPaceMarkerRendersAtElapsedPositionAndMirrorsInRemainingMode() throws {
        let suite = "LimitPaceRendering-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UsageStore(providers: [], autoRefresh: false, defaults: defaults)
        let width = 200.0
        let height = 14.0

        /// 가장 어두운 세로 열의 x — 눈금이 없으면 nil.
        /// tint 를 .clear 로 둬 채움이 칠하지 않게 하므로 눈금만 트랙보다 뚜렷이 어둡다.
        func markerColumn(pace: Double?) throws -> Double? {
            let view = LimitProgressBar(usedPercent: 0, tint: .clear, pace: pace)
                .environment(store).frame(width: width, height: height)
            let host = NSHostingController(rootView: view)
            host.view.frame = NSRect(x: 0, y: 0, width: width, height: height)
            // 창에 넣고 명시 appearance 를 줘야 .primary 가 결정적으로 해석된다.
            let window = NSWindow(contentRect: host.view.frame, styleMask: [.borderless],
                                  backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .aqua)
            window.contentView = host.view
            host.view.layoutSubtreeIfNeeded()
            window.displayIfNeeded()

            let rep = try XCTUnwrap(host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds))
            host.view.cacheDisplay(in: host.view.bounds, to: rep)

            // 열별 최소 밝기 — 눈금은 막대 위아래로 돌출하므로 트랙의 둥근 끝보다 깊게 내려간다.
            var darkest = (column: 0, brightness: 1.0)
            for x in 0..<rep.pixelsWide {
                var minimum = 1.0
                for y in 0..<rep.pixelsHigh {
                    guard let color = rep.colorAt(x: x, y: y),
                          let rgb = color.usingColorSpace(.deviceRGB) else { continue }
                    minimum = min(minimum, rgb.brightnessComponent * rgb.alphaComponent
                                  + (1 - rgb.alphaComponent))
                }
                if minimum < darkest.brightness { darkest = (x, minimum) }
            }
            guard darkest.brightness < 0.6 else { return nil }
            return Double(darkest.column) / Double(rep.pixelsWide) * width
        }

        // 트랙만 있는 상태는 눈금 판정 밝기(0.6)에 닿지 않아야 한다 — 아래 단언들의 전제.
        store.limitDisplayMode = .used
        XCTAssertNil(try markerColumn(pace: nil), "pace 가 없으면 눈금을 그리지 않는다")

        // 창이 1/4 지난 시점: 사용량 모드는 왼쪽에서 25%, 잔량 모드는 75% 지점.
        XCTAssertEqual(try XCTUnwrap(markerColumn(pace: 0.25)), width * 0.25, accuracy: 3)
        store.limitDisplayMode = .remaining
        XCTAssertEqual(try XCTUnwrap(markerColumn(pace: 0.25)), width * 0.75, accuracy: 3)

        // 양 끝에서도 눈금이 막대 밖으로 반쯤 걸치지 않는다.
        store.limitDisplayMode = .used
        XCTAssertEqual(try XCTUnwrap(markerColumn(pace: 0)), 0, accuracy: 3)
        XCTAssertEqual(try XCTUnwrap(markerColumn(pace: 1)), width - 1, accuracy: 3)
    }

    /// 눈금 길이는 오버레이 칸이 아니라 **칠해진 트랙**을 따라야 한다. `ProgressView` 의 칸은
    /// 트랙보다 두 배 높아서, 칸을 기준으로 잡으면 6pt 막대에 16pt 눈금이 붙어 눈금이 막대보다
    /// 커 보였다. 위치 테스트는 어느 쪽이든 통과하므로(가장 어두운 *열*만 본다) 길이를 따로 잰다.
    func testPaceMarkerStaysCloseToPaintedTrackHeight() throws {
        let suite = "LimitPaceHeight-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UsageStore(providers: [], autoRefresh: false, defaults: defaults)
        let width = 200.0
        let height = 20.0

        let view = LimitProgressBar(usedPercent: 0, tint: .clear, pace: 0.5)
            .environment(store).frame(width: width, height: height)
        let host = NSHostingController(rootView: view)
        host.view.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(contentRect: host.view.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host.view
        host.view.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        let rep = try XCTUnwrap(host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds))
        host.view.cacheDisplay(in: host.view.bounds, to: rep)

        /// 투명은 흰색으로 친다 — 트랙/눈금만 배경보다 어둡다.
        func brightness(x: Int, y: Int) -> Double {
            guard let color = rep.colorAt(x: x, y: y),
                  let rgb = color.usingColorSpace(.deviceRGB) else { return 1 }
            return rgb.brightnessComponent * rgb.alphaComponent + (1 - rgb.alphaComponent)
        }
        func paintedRows(column: Int, darkerThan limit: Double) -> Int {
            (0..<rep.pixelsHigh).count { brightness(x: column, y: $0) < limit }
        }

        let scale = Double(rep.pixelsHigh) / height
        let markerColumn = Int(Double(rep.pixelsWide) * 0.5)
        // 눈금에서 몇 pt 떨어진 열 — 트랙만 칠해진 곳.
        let trackOnlyColumn = markerColumn + Int(8 * scale)
        let trackHeight = Double(paintedRows(column: trackOnlyColumn, darkerThan: 0.98)) / scale
        let markerHeight = Double(paintedRows(column: markerColumn, darkerThan: 0.6)) / scale

        XCTAssertGreaterThan(trackHeight, 0, "트랙이 칠해져야 아래 비교가 뜻을 가진다")
        XCTAssertEqual(markerHeight, trackHeight + 4, accuracy: 1,
                       "눈금은 트랙 위아래로 2pt 씩만 물려야 한다 (트랙 \(trackHeight)pt, 눈금 \(markerHeight)pt)")
    }
}
