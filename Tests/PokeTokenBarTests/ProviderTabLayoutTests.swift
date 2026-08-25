import XCTest
import SwiftUI
@testable import PokeTokenBar

// 프로바이더 탭 바 가로 오버플로 가드.
// 등록 프로바이더가 6개가 되면서 캡슐 합계 폭이 팝오버 콘텐츠 폭(332pt)을 넘었고, 줄바꿈을 막지
// 않은 탓에 SwiftUI 가 캡슐 텍스트를 눌러 "Curso/r"·"Code/x" 처럼 단어 중간에서 접었다.
// (5개 시점에 이미 넘고 있었다 — Cursor 추가로 드러났을 뿐이다.)
//
// EvoLineLayoutTests 와 같은 방식으로 트리거 브랜치를 직접 재현한다: 탭들이 실제로 넘치는지까지
// 확인해야 "fit 어서션이 애초에 통과할 조건이었다"는 false confidence 를 막는다.
@MainActor
final class ProviderTabLayoutTests: XCTestCase {

    private func snapshot(_ id: String, _ name: String) -> ProviderSnapshot {
        ProviderSnapshot(providerID: id, displayName: name, today: nil, activeBlock: nil,
                         weekTotal: nil, monthTotal: nil, fetchedAt: Date())
    }

    /// 현재 등록된 전 프로바이더의 표시 이름 — UsageStore.init 기본 배열과 같은 순서.
    private var allProviders: [ProviderSnapshot] {
        [("claude_code", "Claude Code"), ("codex", "Codex"), ("gemini", "Gemini"),
         ("antigravity", "Antigravity"), ("opencode", "OpenCode"), ("hermes", "Hermes Agent"),
         ("cursor", "Cursor"), ("grok", "Grok"), ("copilot", "Copilot"), ("kiro", "Kiro"),
         ("pi", "Pi")]
            .map { snapshot($0.0, $0.1) }
    }

    /// 이 파일의 목록이 실제 레지스트리와 어긋나면 위 가드들은 배포되지 않는 탭 바를 재고 있는 것이다
    /// — Grok 추가 때 목록만 손대고 끝난 것과 같은 표류를 기계로 막는다.
    func testTabListMatchesTheRegisteredProviders() {
        let store = UsageStore(autoRefresh: false,
                               defaults: UserDefaults(suiteName: "ProviderTabLayoutTests.\(UUID().uuidString)")!)
        XCTAssertEqual(allProviders.map(\.providerID), store.registeredProviderIDs,
                       "탭 레이아웃 가드의 프로바이더 목록이 UsageStore.init 기본 배열과 다르다")
    }

    private func bar(_ snaps: [ProviderSnapshot]) -> ProviderTabBar {
        ProviderTabBar(snapshots: snaps, selectedID: snaps.first?.providerID, onSelect: { _ in })
    }

    /// 팝오버가 실제로 제안하는 폭으로 뷰를 재어 렌더 크기를 얻는다.
    private func rendered(_ view: some View, proposing: CGFloat) -> CGSize {
        NSHostingController(rootView: view).sizeThatFits(in: CGSize(width: proposing, height: 600))
    }

    /// 트리거 재현: 스크롤 없이 나열하면 등록된 탭 전부는 팝오버 콘텐츠 폭을 넘는다(= 버그 조건).
    /// 넘치지 않으면 아래 단일 행 검증이 무의미해지므로 이 테스트가 먼저 실패해야 한다.
    func testAllProviderTabsExceedPopoverContentWidthWhenLaidOutInOneRow() {
        let natural = HStack(spacing: 6) {
            ForEach(allProviders) { snap in
                Text(snap.displayName)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        let w = rendered(natural, proposing: .greatestFiniteMagnitude).width
        XCTAssertGreaterThan(w, PopoverMetrics.contentWidth,
                             "\(allProviders.count)개 탭은 한 줄로 펼치면 콘텐츠 폭을 넘어야 한다 — 안 넘으면 이 가드가 무의미하다")
    }

    /// 수정 후: 탭이 다 붙어도 탭 바는 한 행 높이를 유지한다(= 캡슐 텍스트가 접히지 않는다).
    /// 기준선은 탭 2개짜리 바 — 넘치지 않는 대조군이다.
    func testProviderTabBarStaysSingleRowWithAllProviders() {
        let baseline = rendered(bar(Array(allProviders.prefix(2))),
                                proposing: PopoverMetrics.contentWidth).height
        let full = rendered(bar(allProviders), proposing: PopoverMetrics.contentWidth).height
        XCTAssertEqual(full, baseline, accuracy: 0.5,
                       "\(allProviders.count)개 탭 바 높이 \(full) 가 2개 기준선 \(baseline) 을 넘으면 캡슐 텍스트가 접힌 것이다")
    }

    /// 탭 바 자체는 주어진 폭 안에 머문다(넘친 자식이 부모 VStack 을 부풀려 팝오버를 자르지 않게).
    func testProviderTabBarFitsPopoverContentWidth() {
        let w = rendered(bar(allProviders), proposing: PopoverMetrics.contentWidth).width
        XCTAssertLessThanOrEqual(w, PopoverMetrics.contentWidth)
    }

    /// 탭 하나가 단독으로 콘텐츠 폭을 넘으면 스크롤로도 못 구한다 — 새 프로바이더 이름 길이 가드.
    func testNoSingleProviderTabExceedsContentWidth() {
        for snap in allProviders {
            let w = rendered(bar([snap]), proposing: PopoverMetrics.contentWidth).width
            XCTAssertLessThanOrEqual(w, PopoverMetrics.contentWidth,
                                     "\(snap.displayName) 탭 하나가 콘텐츠 폭을 넘는다")
        }
    }
}
