import AppKit
import SwiftUI
import XCTest
@testable import PokeDexBar

/// [회귀] **설정값은 있는데 켤 화면이 없는** 결함. 스프라이트 부드럽게가 섹션을 옮기다 통째로
/// 사라져 어느 화면에서도 못 켜는 상태로 남았다 — `UsageStore` 에는 값이 그대로 있어 저장·로드
/// 테스트는 전부 통과했고, 스크린샷을 눈으로 본 뒤에야 드러났다.
/// 사탕이 상점에서 팔리는데 쓸 화면이 없던 결함과 같은 부류라 같은 방식으로 잠근다:
/// 뷰를 실제로 그려 만들어진 토글 줄을 수집한다.
@MainActor
final class SettingsReachabilityTests: XCTestCase {
    /// 설정 화면을 실제로 그려 토글 줄 라벨을 모은다.
    private func renderedToggleLabels(_ language: AppLanguage = .en) -> [String] {
        let defaults = UserDefaults(suiteName: "settings-\(UUID().uuidString)")!
        let usage = UsageStore(defaults: defaults)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("settings-\(UUID().uuidString).json")
        let player = PlayerStore(fileURL: url, now: { Date(timeIntervalSince1970: 0) },
                                 defaults: defaults)
        player.setLanguage(language)

        SettingsToggleRow.resetConstructed()
        let host = NSHostingView(rootView: SettingsView(onClose: { })
            .environment(usage).environment(player).environment(UpdateChecker())
            .frame(width: PopoverMetrics.width))
        host.layoutSubtreeIfNeeded()
        return SettingsToggleRow.constructed
    }

    /// 두 스프라이트 설정은 성격이 달라 다른 섹션에 있지만, **둘 다 켤 수 있어야 한다.**
    func testBothSpriteSettingsAreReachable() {
        let labels = renderedToggleLabels()
        let l = L(.en)
        XCTAssertTrue(labels.contains(l.antialiasLabel),
                      "스프라이트 부드럽게를 어느 화면에서도 못 켠다: \(labels)")
        XCTAssertTrue(labels.contains(l.fillBoxSlotsLabel),
                      "박스 칸 채우기를 어느 화면에서도 못 켠다: \(labels)")
    }

    /// 다른 화면에도 안 걸린 설정이 없는지 — 지금 켤 수 있어야 하는 토글들을 한 번에 확인한다.
    /// (조건부로 나타나는 것들 — 알림 임계·펫 크기 — 은 상위 토글이 꺼져 있어 여기 안 잡힌다.)
    func testTheAlwaysVisibleTogglesAreAllPresent() {
        let labels = Set(renderedToggleLabels())
        let l = L(.en)
        for expected in [l.antialiasLabel, l.fillBoxSlotsLabel, l.todayTokensShort, l.todayCost,
                         l.limitPercent, l.limitNotificationsLabel, l.updateNotificationsLabel] {
            XCTAssertTrue(labels.contains(expected), "\(expected) 토글이 설정에 없다")
        }
    }

    /// 라벨이 언어를 따라간다 — 영어로만 확인하면 한국어에서 빠진 걸 못 잡는다.
    func testLabelsFollowTheSelectedLanguage() {
        let labels = renderedToggleLabels(.ko)
        XCTAssertTrue(labels.contains(L(.ko).fillBoxSlotsLabel), labels.description)
    }
}
