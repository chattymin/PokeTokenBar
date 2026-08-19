import AppKit
import SwiftUI
import XCTest
@testable import PokeDexBar

/// **배선 테스트** — 기록 함수를 직접 부르는 테스트는 배선이 끊겨 있어도 통과한다.
/// 화면을 실제로 열어서 확인한다.
@MainActor
final class BreadcrumbWiringTests: XCTestCase {
    private var temp: URL!

    override func setUp() async throws {
        try await super.setUp()
        temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("bcw-\(UUID().uuidString).txt")
        Breadcrumbs.fileURL = temp
        Breadcrumbs.reset()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: temp)
        try await super.tearDown()
    }

    private func store() -> PlayerStore {
        PlayerStore(fileURL: FileManager.default.temporaryDirectory
                        .appendingPathComponent("bcw-\(UUID().uuidString).json"),
                    now: { Date(timeIntervalSince1970: 0) },
                    defaults: UserDefaults(suiteName: UUID().uuidString)!)
    }

    private func individual(species: Int, shiny: Bool = false, level: Int = 1,
                            grade: Grade = .common, disguisedAs: Int? = nil,
                            region: Region? = nil) -> Individual {
        var made = Individual(baseID: species, speciesID: species, pathIDs: [species],
                              shiny: shiny, nature: .hardy,
                              exp: GrowthRate.mediumFast.totalExp(at: level),
                              obtainedAt: Date(timeIntervalSince1970: 0), grade: grade,
                              growthRate: .mediumFast)
        made.disguisedAs = disguisedAs
        made.region = region
        return made
    }

    @discardableResult
    private func openDetail(_ made: Individual, store player: PlayerStore) -> NSHostingView<AnyView> {
        let host = NSHostingView(rootView: AnyView(
            IndividualDetailView(store: player, individual: made, line: nil,
                                 onNeedLine: { _ in }, onBack: { })
                .frame(width: PopoverMetrics.width)))
        host.layoutSubtreeIfNeeded()
        return host
    }

    /// **상세 화면을 열면 종 번호가 찍힌다.** 이 제보를 푸는 것이 정확히 이 줄이다.
    func testOpeningADetailViewRecordsTheSpecies() {
        openDetail(individual(species: 133), store: store())
        let lines = Breadcrumbs.read()
        XCTAssertTrue(lines.contains { $0.contains("detail open:") && $0.contains("species=133") },
                      "상세를 열었는데 종 번호가 안 남았다: \(lines)")
    }

    /// 이로치·레벨·등급이 함께 남는다 — 무엇이 특별한 개체였는지 알아야 좁힐 수 있다.
    func testTheDetailBreadcrumbCarriesTheFullIdentity() {
        openDetail(individual(species: 6, shiny: true, level: 42, grade: .rare, region: .alola),
                   store: store())
        let line = Breadcrumbs.read().first { $0.contains("detail open:") } ?? ""
        for needle in ["species=6", "shiny=true", "level=42", "grade=rare", "region=alola"] {
            XCTAssertTrue(line.contains(needle), "\(needle) 가 없다: \(line)")
        }
    }

    /// **위장한 메타몽은 진짜 종과 표시 종을 둘 다 남긴다** — 진단은 진실이 필요하고,
    /// 이 파일은 사용자에게 안 보이는 자리다.
    func testADisguisedIndividualRecordsBothIDs() {
        openDetail(individual(species: 132, disguisedAs: 151), store: store())
        let line = Breadcrumbs.read().first { $0.contains("detail open:") } ?? ""
        XCTAssertTrue(line.contains("species=132"), line)
        XCTAssertTrue(line.contains("display=151"), line)
    }

    /// **같은 개체를 다시 그려도 링이 도배되지 않는다.** SwiftUI 는 같은 뷰를 자주 다시
    /// 만드는데, 그때마다 남기면 링 20칸이 한 줄로 차서 그 앞의 행동이 전부 밀려난다.
    func testRepeatedRendersOfTheSameDetailDoNotFloodTheRing() {
        let player = store()
        let made = individual(species: 25)
        for _ in 0..<8 { openDetail(made, store: player) }
        XCTAssertEqual(Breadcrumbs.read().count, 1, "\(Breadcrumbs.read())")
    }

    /// **대조군 — 다른 개체를 열면 새로 남는다.** 중복 접기가 너무 넓게 잡히면
    /// 두 번째 개체가 통째로 안 남아 진단이 죽는다.
    func testOpeningADifferentIndividualStillRecords() {
        let player = store()
        openDetail(individual(species: 25), store: player)
        openDetail(individual(species: 133), store: player)
        let lines = Breadcrumbs.read()
        XCTAssertEqual(lines.count, 2, "\(lines)")
        XCTAssertTrue(lines[1].contains("species=133"), lines[1])
    }

    /// A → B → A 는 세 번 다 남는다 — 직전 것하고만 비교하기 때문이다.
    func testGoingBackToAPreviousIndividualRecordsAgain() {
        let player = store()
        openDetail(individual(species: 1), store: player)
        openDetail(individual(species: 4), store: player)
        openDetail(individual(species: 1), store: player)
        XCTAssertEqual(Breadcrumbs.read().count, 3, "\(Breadcrumbs.read())")
    }

    /// **사용량 틱은 빵부스러기를 안 남긴다.** 매 갱신마다 남기면 링 20칸이 즉시 밀려
    /// 정작 필요한 행동이 사라지고, 메뉴바 앱의 idle 규율도 깨진다.
    func testTheUsageTickDoesNotRecordBreadcrumbs() {
        let player = store()
        Breadcrumbs.reset()
        for i in 1...30 {
            player.update(todayTokens: i * 1_000_000, todayDate: "2026-08-19", hasUsageData: true)
        }
        XCTAssertTrue(Breadcrumbs.read().isEmpty,
                      "사용량 틱이 빵부스러기를 남긴다: \(Breadcrumbs.read())")
    }

    /// 순수 함수라 조합을 직접 잠근다 — 뷰를 안 띄우고도 형식이 안 깨졌는지 본다.
    func testTheBreadcrumbFormatIsSingleLine() {
        let text = IndividualDetailView.breadcrumb(for: individual(species: 1), hasLine: true)
        XCTAssertFalse(text.contains("\n"))
        XCTAssertTrue(text.hasPrefix("detail open:"), text)
        XCTAssertTrue(text.contains("line=loaded"), text)
    }
}

/// [회귀] `FileManager.urls(for:in:)` 는 배열을 돌려주고 **빈 배열이면 `[0]` 이 프로세스를 죽인다.**
/// 크래시 진단을 넣는 마당에 죽을 수 있는 자리를 남겨 둘 이유가 없어 한 곳으로 모았다.
final class UserDirectorySweepTests: XCTestCase {
    /// 표준 디렉터리들이 다 나오고, 빈 경로가 아니다.
    @MainActor
    func testEveryUsedDirectoryResolves() {
        for dir in [FileManager.SearchPathDirectory.applicationSupportDirectory,
                    .libraryDirectory, .cachesDirectory] {
            XCTAssertFalse(AppEnv.userDirectory(dir).path.isEmpty, "\(dir)")
        }
    }

    /// **소스 스캔 — `[0]` 첨자가 한 군데도 안 남아 있는지.** 한 곳만 고치고 끝내면
    /// 같은 부류가 다른 파일에 그대로 살아 있다(CLAUDE.md 결함 대응 §2 부류 스윕).
    func testNoDirectoryLookupUsesAnIndex() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PokeDexBar")
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)!
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        XCTAssertGreaterThan(files.count, 30, "소스를 못 읽었다 — 이 테스트가 아무것도 안 지킨다")

        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(text.contains("in: .userDomainMask)[0]"),
                           "\(file.lastPathComponent) 이 빈 배열이면 죽는 첨자를 쓴다")
        }
    }
}
