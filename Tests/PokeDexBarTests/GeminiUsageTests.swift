import XCTest
@testable import PokeDexBar

/// Gemini CLI 세션 파싱 — 신규 .jsonl(chatRecordingService) + 레거시 .json, 토큰 매핑·단가.
final class GeminiUsageTests: XCTestCase {
    private var root: URL!
    private var cacheFile: URL!

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ptb-gemini-\(UUID().uuidString)")
        root = base.appendingPathComponent("tmp")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("hash1/chats"), withIntermediateDirectories: true)
        cacheFile = base.appendingPathComponent("usage-cache.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    private let newJSONL = """
    {"type":"session_metadata","sessionId":"s1","startTime":"2026-07-03T01:00:00.000Z"}
    {"type":"user","id":"m1","timestamp":"2026-07-03T01:00:05.000Z","content":[{"text":"hi"}]}
    {"type":"gemini","id":"m2","timestamp":"2026-07-03T01:00:10.000Z","model":"gemini-2.5-pro","tokens":{"input":1000,"output":50,"cached":600,"thoughts":30,"tool":20,"total":1100}}
    {"type":"gemini","id":"m3","timestamp":"2026-07-03T01:01:00.000Z","model":"gemini-2.5-flash","tokens":{"input":10,"output":5,"cached":0,"thoughts":0,"tool":0,"total":15}}
    {"type":"message_update","id":"m3","tokens":{"input":10,"output":8,"cached":0,"thoughts":2,"tool":0,"total":20}}
    """

    private let legacyJSON = """
    {"sessionId":"s0","startTime":"2026-07-02T00:00:00.000Z","messages":[
      {"id":"a1","type":"gemini","timestamp":"2026-07-02T00:10:00.000Z","model":"gemini-2.5-pro","tokens":{"input":100,"output":10,"cached":0,"thoughts":0,"tool":0,"total":110}},
      {"id":"a2","type":"user","content":[{"text":"x"}]}
    ]}
    """

    /// 신규 .jsonl — usageMetadata 의미 보존 매핑 + message_update 가 최종값.
    func testParseNewJSONLMappingAndUpdate() throws {
        let url = root.appendingPathComponent("hash1/chats/session-2026-07-03T01-00-abcd1234.jsonl")
        try newJSONL.write(to: url, atomically: true, encoding: .utf8)
        let entries = LocalUsageReader.parseGeminiFile(url, fmt: LocalUsageReader.localDayFormatter())
        XCTAssertEqual(entries.count, 2, "tokens 있는 메시지 2건(user/metadata 제외)")

        let m2 = entries[0]
        XCTAssertEqual(m2.model, "gemini-2.5-pro")
        XCTAssertEqual(m2.input, 420, "input = (1000-600 비캐시) + 20 tool")
        XCTAssertEqual(m2.cacheRead, 600)
        XCTAssertEqual(m2.output, 80, "output = 50 + 30 thoughts")
        XCTAssertEqual(m2.cacheWrite, 0)
        XCTAssertEqual(m2.total, 1100, "Entry.total == totalTokenCount 보존")

        let m3 = entries[1]
        XCTAssertEqual(m3.output, 10, "message_update(output 8 + thoughts 2)가 최종값")
        XCTAssertEqual(m3.total, 20)
    }

    /// 레거시 .json — messages[] 안의 tokens 만 수집.
    func testParseLegacyJSON() throws {
        let url = root.appendingPathComponent("hash1/chats/checkpoint-old.json")
        try legacyJSON.write(to: url, atomically: true, encoding: .utf8)
        let entries = LocalUsageReader.parseGeminiFile(url, fmt: LocalUsageReader.localDayFormatter())
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].input, 100)
        XCTAssertEqual(entries[0].output, 10)
        XCTAssertEqual(entries[0].total, 110)
    }

    /// 캐시 경로 — .jsonl 과 .json 둘 다 수집되고 (path,mtime,size) 재사용도 동작.
    func testCacheCollectsBothExtensions() async throws {
        try newJSONL.write(to: root.appendingPathComponent("hash1/chats/session-a.jsonl"),
                           atomically: true, encoding: .utf8)
        try legacyJSON.write(to: root.appendingPathComponent("hash1/chats/checkpoint-b.json"),
                             atomically: true, encoding: .utf8)
        let cache = LocalUsageCache(geminiRoot: root, fileURL: cacheFile)
        let entries = await cache.geminiEntries(modifiedSince: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(entries.count, 3, "jsonl 2건 + json 1건")
        XCTAssertEqual(entries.map(\.total).reduce(0, +), 1100 + 20 + 110)
        // 스냅샷에 gemini 캐시가 영속되는지(라운드트립)
        let again = await LocalUsageCache(geminiRoot: root, fileURL: cacheFile)
            .geminiEntries(modifiedSince: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(again.count, 3)
    }

    /// tokens 없는 파일(프롬프트 로그 등)은 조용히 0건.
    func testFileWithoutTokensYieldsNothing() throws {
        let url = root.appendingPathComponent("hash1/logs.json")
        try #"{"entries":[{"sessionId":"x","type":"user","message":"hello"}]}"#
            .write(to: url, atomically: true, encoding: .utf8)
        let entries = LocalUsageReader.parseGeminiFile(url, fmt: LocalUsageReader.localDayFormatter())
        XCTAssertTrue(entries.isEmpty)
    }

    /// Gemini 단가 — 정확 매칭 + pro/flash 패밀리 폴백 + 미지 변형은 0.
    func testGeminiPricing() {
        XCTAssertEqual(ModelPricing.rate(for: "gemini-2.5-pro"), .perMillion(1.25, 10, 0, 0.3125))
        XCTAssertEqual(ModelPricing.rate(for: "gemini-2.5-flash"), .perMillion(0.30, 2.5, 0, 0.075))
        XCTAssertEqual(ModelPricing.rate(for: "gemini-3.1-pro-preview"), .perMillion(1.25, 10, 0, 0.3125))
        XCTAssertEqual(ModelPricing.rate(for: "gemini-3-flash-lite"), .perMillion(0.30, 2.5, 0, 0.075))
        XCTAssertEqual(ModelPricing.rate(for: "gemini-nano-banana"), .zero, "미지 변형은 오표시 방지 위해 0")
        // 실제 비용 산술 (m2 케이스): 420 in + 80 out + 600 cacheR @2.5-pro
        let c = ModelPricing.cost(model: "gemini-2.5-pro", input: 420, output: 80, cacheWrite: 0, cacheRead: 600)
        XCTAssertEqual(c, 420 * 1.25e-6 + 80 * 10e-6 + 600 * 0.3125e-6, accuracy: 1e-12)
    }
}
