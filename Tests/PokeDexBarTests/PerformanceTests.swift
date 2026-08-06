import XCTest
@testable import PokeDexBar

// 성능(measure) + 스케일/비퇴화 검증. baseline 은 머신 의존이라 느슨하게(게이트는 정확성에).

// MARK: 순수 계산 핫패스

final class PureComputePerformanceTests: XCTestCase {
    func testLargeDailyReportDecode() {
        let rows = (0..<1000).map {
            "{\"date\":\"2026-06-\(($0 % 28) + 1)\",\"inputTokens\":\($0),\"outputTokens\":1," +
            "\"cacheCreationTokens\":2,\"cacheReadTokens\":3,\"totalTokens\":\($0),\"totalCost\":0.1}"
        }.joined(separator: ",")
        let json = Data("{\"daily\":[\(rows)]}".utf8)
        measure {
            let report = try! JSONDecoder().decode(DailyReport.self, from: json)
            XCTAssertEqual(report.daily.count, 1000)
        }
    }
}

// MARK: 플로팅 펫 / 스프라이트 idle 배터리 규율

/// 항상 떠 있는 플로팅 펫은 두 번째 GIF 표면이라, 메뉴바에서 고친 idle wakeup 증폭이 재발하지 않게
/// 같은 규율(fps 하한 + 저전력 정적화)을 공유한다. 여기선 그 순수 판정만 고정한다.
@MainActor
final class FloatingPetEnergyTests: XCTestCase {
    /// [회귀] 플로팅 펫 GIF 는 fps 하한(0.4s≈2.5fps)으로 캡 — 네이티브 fps 로 돌면 프레임마다
    /// 재합성(CA 커밋→디스플레이 사이클 wakeup)이 늘어 메뉴바 회귀를 그대로 반복한다.
    func testPetFrameDelayHonorsFloor() {
        XCTAssertEqual(SpriteView.frameDelay(base: 0.1, floor: 0.4), 0.4, accuracy: 1e-9)   // 빠른 프레임 → 캡
        XCTAssertEqual(SpriteView.frameDelay(base: 0.6, floor: 0.4), 0.6, accuracy: 1e-9)   // 이미 느리면 원본 유지
    }

    /// 팝오버 등 일시적 표시(floor=0)는 네이티브 delay 그대로 — 캡은 항상 뜬 펫에만 적용.
    func testTransientSpriteKeepsNativeDelay() {
        XCTAssertEqual(SpriteView.frameDelay(base: 0.1, floor: 0), 0.1, accuracy: 1e-9)
        XCTAssertEqual(SpriteView.frameDelay(base: 0.03, floor: 0), 0.03, accuracy: 1e-9)
    }

    /// 저전력 모드면 펫 애니메이션을 정지(정적)해 배터리를 아낀다. 정상 모드면 애니메이션.
    func testPetFreezesUnderLowPower() {
        XCTAssertFalse(FloatingPetController.shouldAnimate(lowPower: true))
        XCTAssertTrue(FloatingPetController.shouldAnimate(lowPower: false))
    }

    /// 펫은 GIF 원본 속도로 돈다(캡 제거, 2026-08-06). 캡이 없어진 대신 배터리 방어는 저전력
    /// 정적화와 숨김 시 해제가 맡으므로, 그 둘이 살아 있는지를 대신 잠근다.
    func testPetRunsAtNativeSpeed() {
        XCTAssertEqual(FloatingPetView.frameFloor, 0, accuracy: 1e-9, "펫은 원본 속도로 움직인다")
        XCTAssertEqual(SpriteView.frameDelay(base: 0.05, floor: FloatingPetView.frameFloor),
                       0.05, accuracy: 1e-9, "빠른 프레임이 캡에 걸리면 안 된다")
        XCTAssertFalse(FloatingPetController.shouldAnimate(lowPower: true),
                       "캡이 없어진 만큼 저전력 정적화는 반드시 남아 있어야 한다")
    }

    /// Bubble needs headroom + width beyond the square pet size — otherwise content is clipped.
    func testPanelGrowsForBubbleWithoutChangingPetOrigin() {
        let pet: CGFloat = 96
        let idle = FloatingPetController.panelSize(petSize: pet, showingBubble: false)
        XCTAssertEqual(idle, NSSize(width: pet, height: pet))

        let shown = FloatingPetController.panelSize(petSize: pet, showingBubble: true)
        XCTAssertGreaterThan(shown.height, pet, "must reserve vertical headroom for the bubble")
        XCTAssertGreaterThanOrEqual(shown.width, pet)

        let petOrigin = NSPoint(x: 400, y: 200)
        let panelOrigin = FloatingPetController.panelOrigin(
            petOrigin: petOrigin, petSize: pet, panelSize: shown)
        XCTAssertEqual(panelOrigin.y, petOrigin.y, accuracy: 0.5)
        let roundTrip = FloatingPetController.petOrigin(
            panelOrigin: panelOrigin, petSize: pet, panelSize: shown)
        XCTAssertEqual(roundTrip.x, petOrigin.x, accuracy: 0.5)
        XCTAssertEqual(roundTrip.y, petOrigin.y, accuracy: 0.5)
    }

    /// Click opens the popover only when the pointer barely moved; larger movement is a drag.
    func testClickThresholdDistinguishesClickFromDrag() {
        let a = NSPoint(x: 10, y: 10)
        XCTAssertTrue(FloatingPetController.isClick(from: a, to: NSPoint(x: 11, y: 12)))
        XCTAssertTrue(FloatingPetController.isClick(from: a, to: a))
        XCTAssertFalse(FloatingPetController.isClick(from: a, to: NSPoint(x: 20, y: 10)))
    }

    /// Hover tooltip is localized and pure — tokens always; limit % only when provided.
    func testHoverTooltipBuilder() {
        let l = L(.en)
        XCTAssertEqual(
            FloatingPetView.hoverTooltip(todayTokens: 12_345, limitUtilization: nil, l: l),
            l.floatingPetHoverTokensOnly(TokenFormatter.grouped(12_345)))
        XCTAssertEqual(
            FloatingPetView.hoverTooltip(todayTokens: 12_345, limitUtilization: 42, l: l),
            l.floatingPetHoverWithLimit(TokenFormatter.grouped(12_345), TokenFormatter.percent(42)))
    }

    /// Japanese (and ko/en) alert copy must fit the default bubble panel — width-capped wrap,
    /// not intrinsic `.fixedSize` that clipped ja by ~9pt (owner review on #124).
    func testLocalizedAlertBubbleFitsDefaultPanel() {
        let pet: CGFloat = 96
        let panel = FloatingPetController.panelSize(petSize: pet, showingBubble: true)
        XCTAssertEqual(panel.width, FloatingPetController.bubbleMinWidth)
        XCTAssertEqual(panel.height, pet + FloatingPetController.bubbleHeadroom)
        XCTAssertEqual(
            FloatingPetController.bubbleContentWidth
                + FloatingPetController.bubbleHorizontalPadding * 2,
            FloatingPetController.bubbleMinWidth,
            "content column + horizontal padding must equal panel width")

        for lang in [AppLanguage.ko, .en, .ja] {
            let l = L(lang)
            let title = l.notifCritical
            let body = l.notifBody(l.claudeFiveHour, TokenFormatter.percent(85))
            let measured = FloatingPetController.measureSpeechBubble(title: title, body: body)
            XCTAssertLessThanOrEqual(
                measured.width, panel.width + 0.5,
                "\(lang.rawValue) bubble width \(measured.width) must fit panel \(panel.width)")
            XCTAssertLessThanOrEqual(
                measured.height, FloatingPetController.bubbleHeadroom - 2,
                "\(lang.rawValue) bubble height \(measured.height) must fit headroom \(FloatingPetController.bubbleHeadroom)")
        }
    }
}
