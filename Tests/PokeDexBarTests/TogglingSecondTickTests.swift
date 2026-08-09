import AppKit
import SwiftUI
import XCTest
@testable import PokeDexBar

/// 껐다 켤 수 있는 1초 틱.
///
/// 이 타입이 있는 이유는 순전히 결함 하나 때문이다: `TimelineView` 로 감싼 가지와 안 감싼 가지를
/// `if/else` 로 나눠 두면 조건이 뒤집히는 순간 안쪽 뷰의 `@State` 가 날아간다. 마지막 알을 확인할 때
/// 부화 연출이 안 뜨던 게 그것이었다.
@MainActor
final class TogglingSecondTickTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 0)

    /// 꺼져 있으면 **한 번만** 내준다 — 그려 놓고 타이머는 안 돈다.
    /// 알을 한 번도 안 뽑은 사용자에게 매초 재렌더를 시키지 않는다는 에너지 규율이 여기 걸려 있다.
    func testOffYieldsASingleEntry() {
        XCTAssertEqual(TogglingSecondTick(isOn: false).firstEntries(10, from: start), [start])
    }

    /// 켜져 있으면 1초 간격으로 계속 내준다.
    func testOnTicksEverySecond() {
        let entries = TogglingSecondTick(isOn: true).firstEntries(4, from: start)
        XCTAssertEqual(entries, (0..<4).map { start.addingTimeInterval(Double($0)) })
    }

    /// **꺼진 상태에서 켜면 실제로 돌기 시작해야 한다.**
    ///
    /// 여기가 이 수정의 진짜 위험이다. 가지를 없앤 대신 일정 값만 바꾸는데, `TimelineView` 가 바뀐
    /// 일정을 안 집어 들면 알을 새로 뽑아도 카운트다운이 멈춘 채로 남는다 — 고치려던 것보다 나쁜
    /// 회귀다. 그래서 순수 계산이 아니라 **실제로 호스팅해서** 확인한다.
    func testTurningItOnStartsTicking() {
        struct Probe: View {
            let isOn: Bool
            let seen: Counter
            var body: some View {
                TimelineView(TogglingSecondTick(isOn: isOn)) { context in
                    Color.clear.onChange(of: context.date) { _, _ in seen.count += 1 }
                }
            }
        }
        let seen = Counter()
        let host = NSHostingView(rootView: Probe(isOn: false, seen: seen))
        // **화면 밖 창에 붙여야 한다.** `TimelineView` 는 창 없는 호스팅 뷰에서 한 번도 안 돈다
        // (스크린샷 생성기가 같은 이유로 같은 일을 한다).
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 40, height: 40),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -30_000, y: -30_000))
        window.orderBack(nil)
        defer { window.orderOut(nil); window.contentView = nil }
        host.layoutSubtreeIfNeeded()

        pump(2.2)
        XCTAssertEqual(seen.count, 0, "꺼둔 일정이 돌았다 — 타이머가 살아 있다")

        host.rootView = Probe(isOn: true, seen: seen)
        host.layoutSubtreeIfNeeded()
        pump(2.5)
        XCTAssertGreaterThanOrEqual(seen.count, 1, "켰는데 안 돈다 — 바뀐 일정을 안 집어 들었다")
    }

    /// 참조 하나로 콜백 횟수를 센다(뷰 안에서 지역 변수를 못 잡는다).
    @MainActor final class Counter { var count = 0 }

    private func pump(_ seconds: TimeInterval) {
        let until = Date().addingTimeInterval(seconds)
        while Date() < until {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
    }
}

/// 결함 자체를 막는 가드 — 같은 뷰를 두 가지에서 따로 만들면 상태가 날아간다.
final class TimelineBranchGuardTests: XCTestCase {
    /// `PopoverView` 는 `EggSlotsView` 를 **한 번만** 만들어야 한다.
    ///
    /// 두 번 만들던 시절, 조건이 뒤집히면 SwiftUI 가 그걸 다른 뷰로 보고 새로 만들어
    /// `@State hatched` 를 지웠다. 마지막 알에서만 났던 이유는 그때만 조건이 바뀌기 때문이다.
    /// 여기서 세는 것이 곧 그 결함의 형태다.
    func testThePopoverBuildsTheEggSlotsOnlyOnce() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PokeDexBar/UI/PopoverView.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        XCTAssertEqual(text.components(separatedBy: "EggSlotsView(").count - 1, 1,
                       "EggSlotsView 를 여러 가지에서 만들고 있다 — 조건이 뒤집히면 상태가 날아간다")
    }
}
