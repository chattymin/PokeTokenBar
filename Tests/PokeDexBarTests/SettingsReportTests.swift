import AppKit
import SwiftUI
import XCTest
@testable import PokeDexBar

/// 제보 버튼이 **화면에 실제로 있고 눌렀을 때 동작하는지.**
/// (`SettingsToggleRow` 가 별도 타입으로 뽑힌 것과 같은 이유 — 설정이 섹션을 옮기다 통째로
///  사라져 어느 화면에서도 못 켜는 상태로 남았던 적이 있다.)
@MainActor
final class SettingsReportTests: XCTestCase {
    private var opened: [URL] = []
    private var board: NSPasteboard!
    private var crashFile: URL!

    // `async` 오버라이드라야 `@MainActor` 격리가 유지된다 — 동기 `setUp()` 은 nonisolated 라
    // 메인액터 프로퍼티를 건드리면 경고가 난다(이 레포는 경고 0 이 규약이다).
    override func setUp() async throws {
        try await super.setUp()
        opened = []
        // **사용자의 실제 클립보드를 안 건드린다.** 전용 pasteboard 를 주입한다.
        board = NSPasteboard(name: .init("ptb-test-\(UUID().uuidString)"))
        ProblemReport.pasteboard = board
        ProblemReport.openURL = { [weak self] url in self?.opened.append(url); return true }
        crashFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("lc-\(UUID().uuidString).json")
        LastCrash.fileURL = crashFile
        LastCrash.clear()
    }

    override func tearDown() async throws {
        ProblemReport.pasteboard = .general
        ProblemReport.openURL = { NSWorkspace.shared.open($0) }
        board.releaseGlobally()
        try? FileManager.default.removeItem(at: crashFile)
        try await super.tearDown()
    }

    /// 설정 화면을 실제로 그려 제보 버튼들을 모은다.
    @discardableResult
    private func renderSettings(_ language: AppLanguage = .en) -> PlayerStore {
        let defaults = UserDefaults(suiteName: "report-\(UUID().uuidString)")!
        let usage = UsageStore(defaults: defaults)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("report-\(UUID().uuidString).json")
        let player = PlayerStore(fileURL: url, now: { Date(timeIntervalSince1970: 0) },
                                 defaults: defaults)
        player.setLanguage(language)

        SupportActionRow.resetConstructed()
        let host = NSHostingView(rootView: SettingsView(onClose: { })
            .environment(usage).environment(player).environment(UpdateChecker())
            .frame(width: PopoverMetrics.width))
        host.layoutSubtreeIfNeeded()
        return player
    }

    private var labels: [String] { SupportActionRow.constructed.map(\.label) }

    /// 두 버튼이 다 붙어 있다.
    func testBothSupportButtonsAreOnScreen() {
        renderSettings()
        let l = L(.en)
        XCTAssertTrue(labels.contains(l.reportOnGitHub), "GitHub 버튼이 없다: \(labels)")
        XCTAssertTrue(labels.contains(l.copyDiagnostics), "복사 버튼이 없다: \(labels)")
    }

    /// 라벨이 언어를 따라간다 — 영어로만 보면 한국어에서 빠진 걸 못 잡는다.
    func testLabelsFollowTheSelectedLanguage() {
        renderSettings(.ko)
        XCTAssertTrue(labels.contains(L(.ko).copyDiagnostics), labels.description)
    }

    /// **"GitHub" 을 실제로 눌러** 이슈 작성 페이지가 열리는지.
    /// 뷰만 만들고 안 누르면 배선이 끊겨 있어도 통과한다.
    func testTappingGitHubOpensTheIssueForm() throws {
        renderSettings()
        let button = try XCTUnwrap(SupportActionRow.constructed
            .first { $0.label == L(.en).reportOnGitHub })
        button.action()

        XCTAssertEqual(opened.count, 1, "브라우저를 안 열었다 — 배선이 끊겼다")
        let url = try XCTUnwrap(opened.first).absoluteString
        XCTAssertTrue(url.hasPrefix("https://github.com/donky-ey/PokeDexBar/issues/new"), url)
    }

    /// **"복사"를 실제로 눌러** 진단이 클립보드에 들어가는지.
    func testTappingCopyPutsTheDiagnosticsOnThePasteboard() throws {
        renderSettings()
        let button = try XCTUnwrap(SupportActionRow.constructed
            .first { $0.label == L(.en).copyDiagnostics })
        button.action()

        let text = try XCTUnwrap(board.string(forType: .string))
        XCTAssertTrue(text.contains("PokeDexBar:"), text)
        XCTAssertTrue(text.contains("macOS:"), text)
    }

    /// 크래시 기록이 있으면 **그 문맥이 제보에 담긴다** — Task 2·3 의 계약이 화면까지 이어지는지.
    func testTheReportCarriesTheStoredCrashContext() throws {
        LastCrash.save(LastCrashRecord(at: Date(), version: "1.8.0",
                                       crashLines: ["[CRASH] fatal signal SIGTRAP"],
                                       breadcrumbs: ["[t] detail open: species=133 shiny=true"],
                                       acknowledged: false))
        renderSettings()
        let button = try XCTUnwrap(SupportActionRow.constructed
            .first { $0.label == L(.en).copyDiagnostics })
        button.action()

        let text = try XCTUnwrap(board.string(forType: .string))
        XCTAssertTrue(text.contains("species=133"), "크래시 문맥이 제보에 안 담겼다:\n\(text)")
        XCTAssertTrue(text.contains("SIGTRAP"), text)
    }

    /// 제보하면 확인 처리된다 — 배너가 다시 안 뜬다.
    func testReportingAcknowledgesTheCrash() throws {
        LastCrash.save(LastCrashRecord(at: Date(), version: "1", crashLines: [],
                                       breadcrumbs: ["x"], acknowledged: false))
        renderSettings()
        try XCTUnwrap(SupportActionRow.constructed
            .first { $0.label == L(.en).reportOnGitHub }).action()
        XCTAssertEqual(LastCrash.load()?.acknowledged, true)
    }

    /// 브라우저를 못 열면 주소를 안내 문구로 돌려준다(화면이 선택 가능한 텍스트로 띄운다).
    func testABrowserFailureYieldsAFallbackMessage() {
        ProblemReport.openURL = { _ in false }
        let player = renderSettings()
        let message = ProblemReport.openIssue(version: "1.9.0", player: player, l: L(.en))
        XCTAssertNotNil(message)
        XCTAssertTrue(message?.contains("github.com") == true, message ?? "nil")
    }
}
