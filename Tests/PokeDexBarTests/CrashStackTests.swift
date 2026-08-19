import XCTest
@testable import PokeDexBar

/// macOS 크래시 리포트(`.ips`)에서 스택을 뽑아 온다.
///
/// 첫 제보(2026-08-19)가 `SIGABRT` 한 줄뿐이라 미궁이었다 — macOS 는 심볼·소스파일·줄번호까지
/// 담긴 파일을 이미 쓰고 있었는데 그걸 안 읽고 있었다.
final class CrashStackTests: XCTestCase {
    /// 실제 형식 그대로의 픽스처 — 헤더 JSON 한 줄 + 본문 JSON.
    /// **실측한 파일에서 형태를 그대로 옮겼다**(추측한 스키마로 만들면 파서와 픽스처가 같은
    /// 오해를 공유해 둘 다 통과하면서 실파일은 한 건도 못 읽는다 — 이 레포의 #133 부류).
    private let sample = """
    {"app_name":"PokeDexBar","timestamp":"2026-08-19 15:32:08.00 +0900","app_version":"1.9.0"}
    {
      "faultingThread" : 0,
      "exception" : {"type":"EXC_CRASH","signal":"SIGABRT"},
      "termination" : {"indicator":"Abort trap: 6","namespace":"SIGNAL"},
      "threads" : [
        {
          "triggered" : true,
          "frames" : [
            {"imageOffset": 1, "symbol": "__pthread_kill", "imageIndex": 1},
            {"imageOffset": 2, "symbol": "malloc_error_break", "imageIndex": 2},
            {"imageOffset": 3, "symbol": "static SpriteTrim.contentRect(of:)",
             "sourceFile": "SpriteTrim.swift", "sourceLine": 26, "imageIndex": 3}
          ]
        },
        {"frames": [{"imageOffset": 9, "symbol": "start_wqthread", "imageIndex": 1}]}
      ]
    }
    """

    func testItPullsTheCrashedThreadsFrames() throws {
        let lines = try XCTUnwrap(CrashStack.summary(fromIPS: sample))
        let text = lines.joined(separator: "\n")
        XCTAssertTrue(text.contains("EXC_CRASH"), text)
        XCTAssertTrue(text.contains("SIGABRT"), text)
        XCTAssertTrue(text.contains("Abort trap"), text)
        XCTAssertTrue(text.contains("malloc_error_break"), text)
        // **소스 파일과 줄번호까지** — 이게 있어야 추측이 끝난다.
        XCTAssertTrue(text.contains("SpriteTrim.swift:26"), text)
        // 죽지 않은 스레드는 안 담는다 — 잡음이 결론을 가린다.
        XCTAssertFalse(text.contains("start_wqthread"), text)
    }

    /// `faultingThread` 가 없어도 `triggered` 표시로 찾는다 — 둘 중 하나는 늘 있다.
    func testItFallsBackToTheTriggeredFlag() throws {
        let without = sample.replacingOccurrences(of: "\"faultingThread\" : 0,", with: "")
        let text = try XCTUnwrap(CrashStack.summary(fromIPS: without)).joined(separator: "\n")
        XCTAssertTrue(text.contains("malloc_error_break"), text)
    }

    /// 프레임이 너무 많으면 자른다 — 위쪽 몇 개면 원인이 드러나고 아래는 런루프 잡음이다.
    func testItCapsTheNumberOfFrames() throws {
        let many = (0..<80).map { "{\"symbol\": \"frame\($0)\", \"imageIndex\": 1}" }
            .joined(separator: ",")
        let big = sample.replacingOccurrences(
            of: "{\"imageOffset\": 1, \"symbol\": \"__pthread_kill\", \"imageIndex\": 1},",
            with: many + ",")
        let lines = try XCTUnwrap(CrashStack.summary(fromIPS: big))
        XCTAssertLessThanOrEqual(lines.count, CrashStack.maxFrames + 4)
    }

    /// 쓰레기가 들어와도 안 죽는다 — 손상된 리포트나 다른 형식.
    func testGarbageYieldsNothing() {
        XCTAssertNil(CrashStack.summary(fromIPS: "not an ips"))
        XCTAssertNil(CrashStack.summary(fromIPS: "{}\n{not json}"))
        XCTAssertNil(CrashStack.summary(fromIPS: ""))
    }

    /// 본문에 스레드가 없어도 예외·종료 정보는 낸다.
    func testItStillReportsTheSignalWithoutThreads() throws {
        let noThreads = """
        {"app_name":"PokeDexBar"}
        {"exception": {"type":"EXC_BAD_ACCESS","signal":"SIGSEGV"}}
        """
        let text = try XCTUnwrap(CrashStack.summary(fromIPS: noThreads)).joined(separator: "\n")
        XCTAssertTrue(text.contains("SIGSEGV"), text)
    }

    // MARK: 파일 고르기

    /// 리포트 몇 개를 심고 고르기 규칙을 확인한다.
    private func withReports(_ files: [(name: String, ageSeconds: TimeInterval)],
                             _ body: (Date) throws -> Void) throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ips-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let saved = CrashStack.directory
        CrashStack.directory = dir
        defer {
            CrashStack.directory = saved
            try? FileManager.default.removeItem(at: dir)
        }
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        for file in files {
            let url = dir.appendingPathComponent(file.name)
            try sample.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.modificationDate: now.addingTimeInterval(-file.ageSeconds)],
                ofItemAtPath: url.path)
        }
        try body(now)
    }

    /// **오래된 리포트를 이번 크래시라고 붙이면 안 된다** — 진단이 거짓말을 한다.
    func testItIgnoresStaleReports() throws {
        try withReports([("PokeDexBar-old.ips", 7200)]) { now in
            XCTAssertNil(CrashStack.latestReport(appName: "PokeDexBar", now: now, maxAge: 3600))
        }
        // 대조군 — 최근 것은 고른다. 없으면 위 테스트는 늘 통과한다.
        try withReports([("PokeDexBar-fresh.ips", 60)]) { now in
            XCTAssertNotNil(CrashStack.latestReport(appName: "PokeDexBar", now: now, maxAge: 3600))
        }
    }

    /// **다른 앱의 리포트를 붙이면 안 된다.**
    func testItIgnoresOtherApps() throws {
        try withReports([("xctest-2026.ips", 60), ("Safari-2026.ips", 30)]) { now in
            XCTAssertNil(CrashStack.latestReport(appName: "PokeDexBar", now: now, maxAge: 3600))
        }
    }

    /// 여럿이면 **가장 새것**을 고른다.
    func testItPicksTheNewest() throws {
        try withReports([("PokeDexBar-a.ips", 1800), ("PokeDexBar-b.ips", 120)]) { now in
            let picked = try XCTUnwrap(
                CrashStack.latestReport(appName: "PokeDexBar", now: now, maxAge: 3600))
            XCTAssertEqual(picked.lastPathComponent, "PokeDexBar-b.ips")
        }
    }

    /// 개발 빌드("PokeDexBar Dev")도 접두로 잡힌다 — 이름이 갈리는 구조이므로.
    func testTheDevBuildIsMatchedByPrefix() throws {
        try withReports([("PokeDexBar Dev-2026.ips", 60)]) { now in
            XCTAssertNotNil(CrashStack.latestReport(appName: "PokeDexBar Dev",
                                                    now: now, maxAge: 3600))
        }
    }

    /// 끝에서 끝까지 — 파일을 심고 요약까지 나오는지.
    func testEndToEndSummaryFromDisk() throws {
        try withReports([("PokeDexBar-now.ips", 30)]) { now in
            let lines = try XCTUnwrap(
                CrashStack.latestSummary(appName: "PokeDexBar", now: now, maxAge: 3600))
            XCTAssertTrue(lines.joined().contains("SpriteTrim.swift:26"))
        }
    }
}
