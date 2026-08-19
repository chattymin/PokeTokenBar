import XCTest
@testable import PokeDexBar

/// 제보에 담기는 것이 **그 크래시의 것**이어야 한다.
final class LastCrashTests: XCTestCase {
    private var crumbs: URL!
    private var record: URL!

    override func setUp() {
        super.setUp()
        let id = UUID().uuidString
        crumbs = FileManager.default.temporaryDirectory.appendingPathComponent("bc-\(id).txt")
        record = FileManager.default.temporaryDirectory.appendingPathComponent("lc-\(id).json")
        Breadcrumbs.fileURL = crumbs
        LastCrash.fileURL = record
        Breadcrumbs.reset()
        LastCrash.clear()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: crumbs)
        try? FileManager.default.removeItem(at: record)
        super.tearDown()
    }

    // MARK: 합치기 게이트

    /// 비정상 종료였으면 빵부스러기를 합쳐 낸다.
    func testUncleanShutdownYieldsTheBreadcrumbs() {
        Breadcrumbs.record("detail open: species=133 shiny=true")
        let drained = CrashReporter.drainBreadcrumbs(afterUncleanShutdown: true)
        XCTAssertTrue(drained?.contains("species=133") == true, "\(drained ?? "nil")")
    }

    /// **대조군 — 정상 종료였으면 안 합친다.** 매번 합치면 메인 로그가 잡음으로 차서
    /// 2MB 회전이 빨라지고 정작 필요한 이력이 밀려난다.
    func testCleanShutdownYieldsNothing() {
        Breadcrumbs.record("detail open: species=133")
        XCTAssertNil(CrashReporter.drainBreadcrumbs(afterUncleanShutdown: false))
    }

    /// 어느 쪽이든 **파일은 비워진다** — 이번 세션의 흔적에 직전 세션이 섞이면 안 된다.
    func testTheFileIsClearedEitherWay() {
        for unclean in [true, false] {
            Breadcrumbs.record("x")
            _ = CrashReporter.drainBreadcrumbs(afterUncleanShutdown: unclean)
            XCTAssertTrue(Breadcrumbs.read().isEmpty, "unclean=\(unclean)")
        }
    }

    /// 빵부스러기가 없으면 nil — 빈 줄을 로그에 안 남긴다.
    func testNoBreadcrumbsYieldsNothing() {
        XCTAssertNil(CrashReporter.drainBreadcrumbs(afterUncleanShutdown: true))
    }

    // MARK: 보존

    /// **이 기능의 목적 자체.** 크래시 세션의 빵부스러기를 남기고, 기동한 뒤 지금 세션에서
    /// 다른 행동을 여러 개 더 한 다음 기록을 읽어 — 크래시 것이 담기고 지금 것은 안 담기는지.
    /// 살아 있는 링을 읽는 구현은 여기서 반드시 걸린다.
    func testTheStoredRecordHoldsTheCrashSessionNotTheCurrentOne() {
        Breadcrumbs.record("detail open: species=133 shiny=true")
        CrashReporter.captureLastCrash(version: "1.8.0", afterUncleanShutdown: true)
        _ = CrashReporter.drainBreadcrumbs(afterUncleanShutdown: true)

        // 기동 이후의 이번 세션 행동들
        Breadcrumbs.record("tab: settings")
        Breadcrumbs.record("tab: box")

        let stored = LastCrash.load()
        XCTAssertTrue(stored?.breadcrumbs.contains { $0.contains("species=133") } == true,
                      "크래시 세션의 빵부스러기가 없다")
        XCTAssertFalse(stored?.breadcrumbs.contains { $0.contains("tab: settings") } == true,
                       "지금 세션의 행동이 섞여 들어갔다 — 살아 있는 링을 읽고 있다")
    }

    /// **스냅샷은 링을 비우기 전에 뜬다.** 순서가 뒤집히면 빈 기록이 남는다.
    func testTheSnapshotIsTakenBeforeTheRingIsCleared() {
        Breadcrumbs.record("detail open: species=7")
        CrashReporter.captureLastCrash(version: "1.8.0", afterUncleanShutdown: true)
        XCTAssertFalse(LastCrash.load()?.breadcrumbs.isEmpty ?? true,
                       "빈 기록이 남았다 — 비우기가 스냅샷보다 먼저 돌았다")
    }

    /// **대조군 — 정상 종료면 기록을 안 만든다.**
    func testACleanShutdownStoresNoRecord() {
        Breadcrumbs.record("detail open: species=7")
        CrashReporter.captureLastCrash(version: "1.8.0", afterUncleanShutdown: false)
        XCTAssertNil(LastCrash.load())
    }

    /// 크래시 줄도 함께 보존된다.
    func testCrashLinesAreStored() {
        CrashReporter.captureLastCrash(version: "1.8.0", afterUncleanShutdown: true,
                                       crashLines: ["[CRASH] fatal signal SIGTRAP"])
        XCTAssertEqual(LastCrash.load()?.crashLines, ["[CRASH] fatal signal SIGTRAP"])
        XCTAssertEqual(LastCrash.load()?.version, "1.8.0")
    }

    /// 하나만 들고 있는다 — 새 크래시가 옛 기록을 덮고, `acknowledged` 도 함께 풀린다.
    func testANewCrashReplacesTheOldRecordAndReArmsTheBanner() {
        Breadcrumbs.record("detail open: species=7")
        CrashReporter.captureLastCrash(version: "1.8.0", afterUncleanShutdown: true)
        LastCrash.acknowledge()
        XCTAssertEqual(LastCrash.load()?.acknowledged, true)

        Breadcrumbs.reset()
        Breadcrumbs.record("detail open: species=8")
        CrashReporter.captureLastCrash(version: "1.8.0", afterUncleanShutdown: true)
        XCTAssertEqual(LastCrash.load()?.acknowledged, false, "새 크래시인데 배너가 안 재무장됐다")
        XCTAssertTrue(LastCrash.load()?.breadcrumbs.contains { $0.contains("species=8") } == true)
    }

    /// 확인 처리는 저장된다 — 앱을 다시 열어도 배너가 안 뜬다.
    func testAcknowledgePersists() {
        CrashReporter.captureLastCrash(version: "1", afterUncleanShutdown: true)
        LastCrash.acknowledge()
        XCTAssertEqual(LastCrash.load()?.acknowledged, true)
    }

    /// 기록이 없을 때 확인 처리를 불러도 안 죽고, 없는 기록을 만들지도 않는다.
    func testAcknowledgingNothingIsHarmless() {
        LastCrash.acknowledge()
        XCTAssertNil(LastCrash.load())
    }

    /// 깨진 JSON 이 있어도 안 죽는다 — 손댄 파일이나 중간에 끊긴 write.
    func testACorruptRecordIsTreatedAsAbsent() {
        try? Data("not json".utf8).write(to: record)
        XCTAssertNil(LastCrash.load())
    }
}
