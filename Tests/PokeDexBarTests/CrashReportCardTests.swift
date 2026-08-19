import AppKit
import SwiftUI
import XCTest
@testable import PokeDexBar

/// 크래시에서 제보까지 흐름을 잇는 카드. **이것이 없으면 진단 기능 전체가 아무 일도 안 한다** —
/// 사용자가 스스로 설정에 들어갈 이유가 없다.
@MainActor
final class CrashReportCardTests: XCTestCase {
    private var opened: [URL] = []
    private var crashFile: URL!

    override func setUp() async throws {
        try await super.setUp()
        opened = []
        ProblemReport.openURL = { [weak self] url in self?.opened.append(url); return true }
        crashFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("lc-\(UUID().uuidString).json")
        LastCrash.fileURL = crashFile
        LastCrash.clear()
    }

    override func tearDown() async throws {
        ProblemReport.openURL = { NSWorkspace.shared.open($0) }
        try? FileManager.default.removeItem(at: crashFile)
        try await super.tearDown()
    }

    private func store() -> PlayerStore {
        let defaults = UserDefaults(suiteName: "crash-\(UUID().uuidString)")!
        return PlayerStore(fileURL: FileManager.default.temporaryDirectory
                            .appendingPathComponent("crash-\(UUID().uuidString).json"),
                           now: { Date(timeIntervalSince1970: 0) }, defaults: defaults)
    }

    private func record(acknowledged: Bool, species: Int = 133) -> LastCrashRecord {
        LastCrashRecord(at: Date(timeIntervalSince1970: 1_700_000_000), version: "1.9.0",
                        crashLines: ["[CRASH] fatal signal SIGTRAP"],
                        breadcrumbs: ["[t] detail open: species=\(species) shiny=true"],
                        acknowledged: acknowledged)
    }

    /// 카드를 실제로 그린다. 돌아오는 값은 "지금 떴나".
    @discardableResult
    private func render(_ player: PlayerStore) -> Bool {
        CrashReportCard.resetConstructed()
        let host = NSHostingView(rootView: CrashReportCard(store: player, version: "1.9.0")
            .frame(width: PopoverMetrics.width))
        host.layoutSubtreeIfNeeded()
        return CrashReportCard.bodyEvaluations.contains(true)
    }

    // MARK: 순수 판정

    func testShouldShowIsGatedOnBothConditions() {
        XCTAssertFalse(CrashReportCard.shouldShow(nil))
        XCTAssertTrue(CrashReportCard.shouldShow(record(acknowledged: false)))
        XCTAssertFalse(CrashReportCard.shouldShow(record(acknowledged: true)))
    }

    // MARK: 게이트 — 대조군 셋

    /// 크래시 기록이 있고 아직 확인 전이면 뜬다.
    func testTheCardAppearsForAnUnacknowledgedCrash() {
        LastCrash.save(record(acknowledged: false))
        XCTAssertTrue(render(store()), "크래시가 있는데 배너가 안 뜬다")
    }

    /// **대조군 ① — 기록이 없으면 안 뜬다.**
    func testNoCardWithoutACrash() {
        XCTAssertFalse(render(store()), "크래시가 없는데 배너가 떴다")
    }

    /// **대조군 ② — 이미 확인했으면 안 뜬다.** 같은 크래시로 매번 조르면 배경이 된다.
    func testNoCardOnceAcknowledged() {
        LastCrash.save(record(acknowledged: true))
        XCTAssertFalse(render(store()), "확인했는데 배너가 또 떴다")
    }

    /// **대조군 ③ — 새 크래시가 나면 다시 뜬다.** 게이트가 한 번 닫히고 영영 안 열리면
    /// 두 번째 크래시부터 아무도 제보하지 않는다.
    func testTheCardComesBackForANewCrash() {
        LastCrash.save(record(acknowledged: true))
        XCTAssertFalse(render(store()))
        LastCrash.save(record(acknowledged: false, species: 25))
        XCTAssertTrue(render(store()), "새 크래시인데 배너가 안 뜬다")
    }

    // MARK: 배선 — 실제로 누른다

    /// **"닫기"를 실제로 눌러** 확인 처리가 저장되고, 다시 그리면 안 뜨는지.
    func testTappingDismissPersistsTheAcknowledgement() throws {
        LastCrash.save(record(acknowledged: false))
        let player = store()
        render(player)
        try XCTUnwrap(CrashReportCard.constructed.first).dismiss()

        XCTAssertEqual(LastCrash.load()?.acknowledged, true, "확인 처리가 저장 안 됐다")
        XCTAssertFalse(render(player), "닫았는데 다시 뜬다")
    }

    /// **"제보하기"를 실제로 눌러** 이슈가 열리고 확인 처리까지 되는지.
    /// 뷰만 만들고 안 누르면 배선이 끊겨 있어도 통과한다.
    func testTappingReportOpensTheIssueAndAcknowledges() throws {
        LastCrash.save(record(acknowledged: false))
        let player = store()
        render(player)
        try XCTUnwrap(CrashReportCard.constructed.first).report()

        XCTAssertEqual(opened.count, 1, "브라우저를 안 열었다 — 배선이 끊겼다")
        XCTAssertEqual(LastCrash.load()?.acknowledged, true)
        XCTAssertFalse(render(player), "제보했는데 배너가 또 뜬다")
    }

    /// 카드가 넘기는 진단에 **그 크래시의** 빵부스러기가 담긴다 —
    /// Task 2·3 의 계약이 화면까지 실제로 이어지는지 끝에서 확인한다.
    func testTheCardsReportCarriesTheCrashBreadcrumbs() throws {
        LastCrash.save(record(acknowledged: false))
        let player = store()
        render(player)
        try XCTUnwrap(CrashReportCard.constructed.first).report()

        let url = try XCTUnwrap(opened.first).absoluteString.removingPercentEncoding ?? ""
        XCTAssertTrue(url.contains("species=133"), "크래시 문맥이 이슈에 안 담겼다:\n\(url)")
        XCTAssertTrue(url.contains("SIGTRAP"), url)
    }

    /// 홈 탭이 이 카드를 **실제로 만든다.** 카드가 훌륭해도 홈에 안 붙어 있으면 소용이 없다.
    func testTheHomeTabBuildsTheCard() {
        LastCrash.save(record(acknowledged: false))
        let player = store()
        XCTAssertNotNil(player.chooseStarter(speciesID: StarterCatalog.all[0], grade: .common))

        CrashReportCard.resetConstructed()
        let host = NSHostingView(rootView: PopoverView(player: player,
                                                       provider: StubCrashCardProvider())
            .environment(UsageStore())
            .environment(player)
            .environment(UpdateChecker())
            .environment(PopoverNavigation())
            .frame(width: PopoverMetrics.width))
        host.layoutSubtreeIfNeeded()

        XCTAssertFalse(CrashReportCard.bodyEvaluations.isEmpty,
                       "홈 탭이 크래시 카드를 아예 안 만든다 — 배선이 없다")
    }
}

/// 홈 탭 호스팅용 — 네트워크를 안 탄다.
private struct StubCrashCardProvider: PokeProviding {
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: baseSpeciesID, tree: EvoNode(speciesID: baseSpeciesID, children: []),
                rarity: .common, names: [:])
    }
}
