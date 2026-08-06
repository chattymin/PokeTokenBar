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

/// 개발 빌드와 정식 설치본을 **나란히** 깔고 쓰기 위한 분리. 같은 이름을 쓰면 세이브·사용량
/// 캐시·로그를 서로 덮어써서, 시험 삼아 한 일이 실제 진행에 섞인다.
final class StorageNamespaceTests: XCTestCase {
    /// 테스트·로우 바이너리에서는 예전 이름 그대로 — 기존 세이브 경로가 바뀌면 안 된다.
    @MainActor
    func testUnbundledRunKeepsTheOriginalName() {
        XCTAssertEqual(AppEnv.storageName, "PokeDexBar")
        XCTAssertFalse(AppEnv.isDevBuild)
    }

    /// 저장 경로가 이름에서 파생돼야 개발 빌드가 자동으로 갈라진다 —
    /// 어느 한 곳이라도 "PokeDexBar" 를 직접 적어 두면 그 파일만 두 앱이 공유하게 된다.
    @MainActor
    func testEveryStoredPathDerivesFromTheNamespace() {
        let support = AppEnv.supportDirectory().path
        XCTAssertTrue(support.hasSuffix("/\(AppEnv.storageName)"), support)
        XCTAssertTrue(PlayerStore.defaultURL().path.hasPrefix(support),
                      "세이브가 이름 공간 밖에 있다 — 두 빌드가 같은 파일을 쓴다")
    }

    /// 로그인 항목 레이블은 번들 ID 를 따라가야 한다 — 고정이면 한쪽을 켤 때 다른 쪽이 꺼진다.
    @MainActor
    func testLoginItemLabelFollowsTheBundle() {
        XCTAssertTrue(LoginItem.label.hasSuffix(".login"))
        XCTAssertTrue(LoginItem.plistName.hasPrefix(LoginItem.bundleID))
    }
}
