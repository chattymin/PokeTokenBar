import XCTest
@testable import PokeDexBar

/// 빵부스러기 — **동기로** 써야만 의미가 있다. 죽는 그 런루프에서 이미 쓰였어야 하기 때문이다.
final class BreadcrumbsTests: XCTestCase {
    private var temp: URL!

    override func setUp() {
        super.setUp()
        temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("bc-\(UUID().uuidString).txt")
        Breadcrumbs.fileURL = temp
        Breadcrumbs.reset()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: temp)
        super.tearDown()
    }

    /// **이 기능이 존재하는 이유.** `record` 가 돌아온 직후 파일에 이미 있어야 한다 —
    /// 비동기로 넘기면 크래시가 그 사이에 일어나 아무것도 안 남는다.
    func testRecordIsOnDiskBeforeItReturns() {
        Breadcrumbs.record("detail open: species=133")
        // 기다리지 않는다. 여기서 파일을 바로 읽는다.
        let text = try? String(contentsOf: temp, encoding: .utf8)
        XCTAssertNotNil(text, "record 가 돌아왔는데 파일이 없다 — 비동기로 쓰고 있다")
        XCTAssertTrue(text?.contains("species=133") == true, "\(text ?? "nil")")
    }

    /// 링은 최근 `capacity` 개만 남긴다.
    func testTheRingKeepsOnlyTheMostRecent() {
        for i in 0..<(Breadcrumbs.capacity + 5) { Breadcrumbs.record("line \(i)") }
        let lines = Breadcrumbs.read()
        XCTAssertEqual(lines.count, Breadcrumbs.capacity)
        XCTAssertFalse(lines.contains { $0.contains("line 0 ") || $0.hasSuffix("line 0") },
                       "오래된 줄이 안 빠졌다")
        XCTAssertTrue(lines.contains { $0.hasSuffix("line \(Breadcrumbs.capacity + 4)") },
                      "가장 최근 줄이 없다")
    }

    /// 순서가 유지된다 — 시간순으로 읽혀야 무슨 일이 있었는지 재구성할 수 있다.
    func testOrderIsOldestFirst() {
        Breadcrumbs.record("first")
        Breadcrumbs.record("second")
        let lines = Breadcrumbs.read()
        XCTAssertTrue(lines[0].hasSuffix("first"), lines[0])
        XCTAssertTrue(lines[1].hasSuffix("second"), lines[1])
    }

    /// 각 줄에 시각이 붙는다 — 언제 열었는지가 있어야 로그의 다른 줄과 맞춰 볼 수 있다.
    func testEachLineIsTimestamped() {
        Breadcrumbs.record("detail open: species=1")
        // `[0]` 로 꺼내지 않는다 — 기록이 없으면 테스트가 *실패*해야지 크래시로 스위트를
        // 통째로 중단시키면 안 된다(돌연변이 확인에서 실제로 그렇게 됐다).
        XCTAssertEqual(Breadcrumbs.read().first?.hasPrefix("["), true, "시각 접두가 없다")
    }

    func testClearEmptiesBothTheRingAndTheFile() {
        Breadcrumbs.record("x")
        Breadcrumbs.clear()
        XCTAssertTrue(Breadcrumbs.read().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.path))
    }

    /// 비운 뒤에 다시 남기면 **옛 줄이 안 돌아온다** — 링을 비우지 않고 파일만 지우면
    /// 다음 `record` 가 메모리에 남은 옛 줄까지 통째로 다시 쓴다.
    func testRecordingAfterAClearDoesNotResurrectOldLines() {
        Breadcrumbs.record("old")
        Breadcrumbs.clear()
        Breadcrumbs.record("new")
        let lines = Breadcrumbs.read()
        XCTAssertEqual(lines.count, 1, "\(lines)")
        XCTAssertTrue(lines[0].hasSuffix("new"))
    }

    /// 파일이 없어도 안 죽는다(첫 실행).
    func testReadingWithNoFileIsEmpty() {
        XCTAssertTrue(Breadcrumbs.read().isEmpty)
    }

    /// 개행이 든 줄을 넣어도 링이 안 망가진다 — 파일이 줄 단위로 읽히므로.
    func testNewlinesInAMessageDoNotBreakTheRing() {
        Breadcrumbs.record("a\nb")
        Breadcrumbs.record("c")
        XCTAssertEqual(Breadcrumbs.read().count, 2, "한 줄이 두 줄로 쪼개졌다")
    }
}
