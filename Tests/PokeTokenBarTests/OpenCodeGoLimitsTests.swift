import SQLite3
import XCTest
@testable import PokeTokenBar

final class OpenCodeGoLimitsTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("opencode-go-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        OpenCodeGoRateLimitsProvider.transportForTesting = nil
        try? FileManager.default.removeItem(at: root)
    }

    /// Response captured from the live endpoint (2026-10-30).
    private let livePayload = """
    {"usage":{"rolling":{"status":"ok","percent":36,"resetsAt":"2026-10-29T15:52:06.000Z"},\
    "weekly":{"status":"ok","percent":34,"resetsAt":"2026-11-02T00:00:00.000Z"},\
    "monthly":{"status":"ok","percent":30,"resetsAt":"2026-11-16T23:16:57.000Z"}}}
    """

    // MARK: Decoding and window state

    func testDecodesTheConsoleUsagePayload() throws {
        let status = try JSONDecoder().decode(OpenCodeGoRateLimitStatus.self, from: Data(livePayload.utf8))
        XCTAssertTrue(status.hasVisibleLimit)
        XCTAssertEqual(status.rolling?.percent, 36)
        XCTAssertEqual(status.weekly?.percent, 34)
        XCTAssertEqual(status.monthly?.percent, 30)
        XCTAssertEqual(status.monthly?.status, "ok")
        XCTAssertNotNil(status.weekly?.resetDate)
    }

    /// An unknown status or a fractional percentage must not drop the window.
    func testUnknownStatusAndFractionalPercentStillDecode() throws {
        let json = #"{"usage":{"rolling":{"status":"exceeded","percent":101.5}}}"#
        let status = try JSONDecoder().decode(OpenCodeGoRateLimitStatus.self, from: Data(json.utf8))
        XCTAssertEqual(status.rolling?.percent, 101.5)
        XCTAssertEqual(status.rolling?.status, "exceeded")
        XCTAssertNil(status.weekly)
        XCTAssertTrue(status.hasVisibleLimit)
    }

    func testEmptyUsageHasNoVisibleLimit() throws {
        let status = try JSONDecoder().decode(OpenCodeGoRateLimitStatus.self, from: Data(#"{"usage":{}}"#.utf8))
        XCTAssertFalse(status.hasVisibleLimit)
    }

    func testRunningWindowKeepsItsPercentAndReset() {
        let now = Date()
        let reset = now.addingTimeInterval(3600)
        let window = OpenCodeGoWindow(percent: 36, resetsAt: ISO8601DateFormatter().string(from: reset))
        XCTAssertFalse(window.hasEnded(now: now))
        XCTAssertEqual(window.utilization(now: now), 36)
        XCTAssertEqual(window.activeReset(now: now)?.timeIntervalSince1970 ?? 0,
                       reset.timeIntervalSince1970, accuracy: 1)
    }

    /// The server keeps reporting the last rolling window after it ended (36% with yesterday's reset).
    func testEndedWindowCountsAsUnused() {
        let now = Date()
        let window = OpenCodeGoWindow(percent: 36,
                                      resetsAt: ISO8601DateFormatter().string(from: now.addingTimeInterval(-60)))
        XCTAssertTrue(window.hasEnded(now: now))
        XCTAssertEqual(window.utilization(now: now), 0)
        XCTAssertNil(window.activeReset(now: now))
    }

    func testWindowWithoutResetIsNotEnded() {
        let window = OpenCodeGoWindow(percent: 12)
        XCTAssertFalse(window.hasEnded(now: Date()))
        XCTAssertEqual(window.utilization(now: Date()), 12)
    }

    // MARK: Provider

    func testNoKeyReturnsNilWithoutARequest() async throws {
        OpenCodeGoRateLimitsProvider.transportForTesting = { _ in
            XCTFail("no request without a key")
            return nil
        }
        let status = try await OpenCodeGoRateLimitsProvider(apiKey: { nil }).fetch()
        XCTAssertNil(status)
    }

    func testFetchSendsTheKeyAsBearer() async throws {
        let payload = livePayload
        OpenCodeGoRateLimitsProvider.transportForTesting = { request in
            XCTAssertEqual(request.httpMethod ?? "GET", "GET")
            XCTAssertEqual(request.url, OpenCodeGoRateLimitsProvider.usageURL)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
            return (Data(payload.utf8), 200)
        }
        let status = try await OpenCodeGoRateLimitsProvider(apiKey: { "sk-test" }).fetch()
        XCTAssertEqual(status?.weekly?.percent, 34)
    }

    func testRejectedKeyThrowsTheStatusCode() async {
        OpenCodeGoRateLimitsProvider.transportForTesting = { _ in (Data(), 401) }
        do {
            _ = try await OpenCodeGoRateLimitsProvider(apiKey: { "sk-old" }).fetch()
            XCTFail("expected a throw")
        } catch {
            XCTAssertEqual(error as? LimitsError, .httpStatus(401))
        }
    }

    func testRateLimitedThrowsRateLimited() async {
        OpenCodeGoRateLimitsProvider.transportForTesting = { _ in (Data(), 429) }
        do {
            _ = try await OpenCodeGoRateLimitsProvider(apiKey: { "sk-test" }).fetch()
            XCTFail("expected a throw")
        } catch {
            XCTAssertEqual(error as? LimitsError, .rateLimited(retryAfter: nil))
        }
    }

    /// The real transport stops at the gate inside `swift test`, so the key never reaches the network.
    func testLiveTransportIsGatedUnderSwiftTest() async throws {
        if AppEnv.isParityRun { throw XCTSkip("PTB_PARITY=1 opens the gate on purpose") }
        do {
            _ = try await OpenCodeGoRateLimitsProvider(apiKey: { "sk-test" }).fetch()
            XCTFail("a live OpenCode Go limits call ran inside swift test")
        } catch {
            XCTAssertEqual(error as? LimitsError, .liveFetchNotPermitted)
        }
    }

    // MARK: Key lookup

    func testKeyComesFromTheActiveCredentialRow() throws {
        try makeCredentialDatabase(rows: [
            ("opencode-go", 0, #"{"type":"key","key":"stale"}"#, 3),
            ("opencode-go", 1, #"{"type":"key","key":"  fresh  "}"#, 2),
            ("opencode", 1, #"{"type":"oauth","access":"x"}"#, 4),
        ])
        XCTAssertEqual(LocalAdditionalUsageReader.openCodeAPIKey(integrationID: "opencode-go", roots: [root]), "fresh")
    }

    func testOAuthCredentialIsNotAKey() throws {
        try makeCredentialDatabase(rows: [("opencode-go", 1, #"{"type":"oauth","access":"x"}"#, 1)])
        XCTAssertNil(LocalAdditionalUsageReader.openCodeAPIKey(integrationID: "opencode-go", roots: [root]))
    }

    /// OpenCode 1.x wrote keys to `auth.json`; a database without the row falls back to it.
    func testFallsBackToAuthJSON() throws {
        try makeCredentialDatabase(rows: [("openrouter", 1, #"{"type":"key","key":"or"}"#, 1)])
        try Data(#"{"opencode-go":{"type":"api","key":"legacy"},"x":{"type":"key","key":"other"}}"#.utf8)
            .write(to: root.appendingPathComponent("auth.json"))
        // `auth.json` labels API keys "api", the credential table "key".
        XCTAssertEqual(LocalAdditionalUsageReader.openCodeAPIKey(integrationID: "opencode-go", roots: [root]), "legacy")
    }

    func testNoCredentialsAnywhereIsNil() {
        XCTAssertNil(LocalAdditionalUsageReader.openCodeAPIKey(integrationID: "opencode-go", roots: [root]))
    }

    private func makeCredentialDatabase(rows: [(String, Int, String, Int)]) throws {
        var database: OpaquePointer?
        let url = root.appendingPathComponent("opencode.db")
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        var sql = """
        CREATE TABLE credential (id text PRIMARY KEY, integration_id text, label text NOT NULL,
          value text NOT NULL, connector_id text, method_id text, active integer,
          time_created integer NOT NULL, time_updated integer NOT NULL);
        """
        for (index, row) in rows.enumerated() {
            let value = row.2.replacingOccurrences(of: "'", with: "''")
            sql += "INSERT INTO credential VALUES ('c\(index)', '\(row.0)', 'l', '\(value)', NULL, NULL, \(row.1), 0, \(row.3));"
        }
        XCTAssertEqual(sqlite3_exec(database, sql, nil, nil, nil), SQLITE_OK)
    }
}
