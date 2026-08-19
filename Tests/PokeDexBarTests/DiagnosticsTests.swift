import XCTest
@testable import PokeDexBar

final class DiagnosticsTests: XCTestCase {

    // MARK: 경로 지우기

    /// **홈 경로가 지워진다.** 공개 이슈에 실명이 새면 안 된다.
    func testHomePathIsRedacted() {
        let text = "cache at /Users/dongmin/Library/Caches/PokeDexBar/x.gif"
        let out = Diagnostics.redact(text, home: "/Users/dongmin")
        XCTAssertFalse(out.contains("dongmin"), out)
        XCTAssertTrue(out.contains("~/Library/Caches/PokeDexBar/x.gif"), out)
    }

    /// 여러 번 나와도 전부 지운다.
    func testEveryOccurrenceIsRedacted() {
        let out = Diagnostics.redact("/Users/a/x and /Users/a/y", home: "/Users/a")
        XCTAssertFalse(out.contains("/Users/a"), out)
    }

    /// **대조군 — 경로가 아닌 것은 그대로 남는다.** 지우기가 너무 넓게 잡히면
    /// 진단이 통째로 뭉개져 이슈가 쓸모없어진다.
    func testNonPathTextSurvivesRedaction() {
        let text = "detail open: species=133 shiny=true level=42"
        XCTAssertEqual(Diagnostics.redact(text, home: "/Users/dongmin"), text)
    }

    /// 홈이 비었거나 `/` 면 아무것도 안 지운다 — 전부 `~` 로 바뀌면 진단이 죽는다.
    func testADegenerateHomeDoesNotEatEverything() {
        let text = "/Users/a/x"
        XCTAssertEqual(Diagnostics.redact(text, home: ""), text)
        XCTAssertEqual(Diagnostics.redact(text, home: "/"), text)
    }

    // MARK: 리포트 본문

    private func record(_ crumbs: [String]) -> LastCrashRecord {
        LastCrashRecord(at: Date(timeIntervalSince1970: 1_700_000_000), version: "1.8.0",
                        crashLines: ["[CRASH] fatal signal SIGTRAP"], breadcrumbs: crumbs,
                        acknowledged: false)
    }

    func testTheReportCarriesVersionOsAndBreadcrumbs() {
        let text = Diagnostics.report(version: "1.8.0", os: "Version 26.5",
                                      lastCrash: record(["[t] detail open: species=133"]),
                                      boxCount: 12, dexCount: 40)
        for needle in ["1.8.0", "26.5", "species=133", "SIGTRAP"] {
            XCTAssertTrue(text.contains(needle), "\(needle) 가 없다:\n\(text)")
        }
    }

    /// **크래시 기록이 있는지 없는지가 양쪽 다 표시된다** — 크래시가 아닌 제보(기능 문의)도
    /// 이 경로로 오므로, "정상"이 조용히 생략되면 읽는 사람이 구분할 수 없다.
    func testTheCrashPresenceIsStatedEitherWay() {
        let crashed = Diagnostics.report(version: "1", os: "o", lastCrash: record([]),
                                         boxCount: 0, dexCount: 0)
        let clean = Diagnostics.report(version: "1", os: "o", lastCrash: nil,
                                       boxCount: 0, dexCount: 0)
        XCTAssertNotEqual(crashed, clean)
        XCTAssertTrue(clean.contains("No unexpected shutdown"), clean)
    }

    /// 크래시 기록이 없어도 제보는 만들어진다 — 기능 문의로도 쓸 수 있어야 한다.
    func testAReportWithoutACrashStillCarriesTheVersion() {
        let text = Diagnostics.report(version: "1.8.0", os: "o", lastCrash: nil,
                                      boxCount: 0, dexCount: 0)
        XCTAssertTrue(text.contains("1.8.0"))
    }

    /// **세이브 내용은 안 들어간다.** 규모(개수)만 넣는다.
    func testTheReportDoesNotCarrySaveContents() {
        let text = Diagnostics.report(version: "1", os: "o", lastCrash: nil,
                                      boxCount: 12, dexCount: 40)
        XCTAssertTrue(text.contains("12"))
        XCTAssertFalse(text.lowercased().contains("earnedtokens"))
        XCTAssertFalse(text.lowercased().contains("partnerid"))
    }

    // MARK: URL 조립

    private func longBody(_ n: Int) -> String {
        (0..<n).map { "[2026-08-19T00:00:00Z] detail open: species=\($0) 상세 화면 진입" }
            .joined(separator: "\n")
    }

    func testTheURLPointsAtTheNewIssueForm() {
        let made = Diagnostics.issueURL(title: "t", body: "b")
        XCTAssertTrue(made!.url.absoluteString
            .hasPrefix("https://github.com/donky-ey/PokeDexBar/issues/new"),
                      made!.url.absoluteString)
    }

    /// 짧은 본문은 안 잘린다.
    func testAShortBodyIsNotTruncated() {
        XCTAssertEqual(Diagnostics.issueURL(title: "crash", body: "short")?.truncated, false)
    }

    /// **긴 본문은 잘리되 URL 이 한도 안에 들어오고 여전히 유효하다.**
    /// 한글은 percent-encoding 으로 세 배가 되므로 인코딩 *후* 길이로 재야 한다.
    func testALongBodyIsTruncatedUnderTheLimit() {
        let made = Diagnostics.issueURL(title: "crash", body: longBody(400))
        XCTAssertNotNil(made)
        XCTAssertTrue(made!.truncated)
        XCTAssertLessThanOrEqual(made!.url.absoluteString.count, Diagnostics.urlLimit)
    }

    /// **자르기는 뒤에서부터다 — 앞의 버전 정보는 반드시 남는다.**
    /// 앞을 먹으면 이슈에 버전이 없어 아무 쓸모가 없다.
    func testTruncationKeepsTheHead() {
        let body = "PokeDexBar 1.8.0 / macOS 26.5\n" + longBody(400)
        let made = Diagnostics.issueURL(title: "crash", body: body)
        XCTAssertTrue(made!.url.absoluteString.contains("1.8.0"),
                      "버전이 잘려 나갔다 — 자르기가 앞을 먹고 있다")
    }

    /// **잘렸을 때만 안내가 붙는다** — 양쪽 다 본다.
    func testTheTruncationNoteAppearsOnlyWhenTruncated() {
        let short = Diagnostics.issueURL(title: "t", body: "short")!
        XCTAssertFalse(short.url.absoluteString.contains("truncated"))

        let long = Diagnostics.issueURL(title: "t", body: longBody(400))!
        XCTAssertTrue(long.url.absoluteString.contains("truncated"),
                      "잘렸는데 안내가 없다 — 사용자가 전체 로그를 못 찾는다")
    }

    /// 한도가 아주 작아도 안 죽고 유효한 URL 을 돌려준다.
    func testAnAbsurdlySmallLimitStillYieldsAURL() {
        let made = Diagnostics.issueURL(title: "t", body: longBody(50), limit: 80)
        XCTAssertNotNil(made)
        XCTAssertEqual(made?.truncated, true)
    }
}
