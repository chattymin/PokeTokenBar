import XCTest
@testable import PokeTokenBar

final class PiUsageTests: XCTestCase {
    private var base: URL!
    private var rootA: URL!
    private var rootB: URL!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory
            .appendingPathComponent("PokeTokenBar-PiUsageTests-\(UUID().uuidString)")
        rootA = base.appendingPathComponent("a")
        rootB = base.appendingPathComponent("b")
        try FileManager.default.createDirectory(at: rootA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rootB, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: base)
    }

    private func usage(
        input: Any = 0, output: Any = 0, reasoning: Any? = nil,
        cacheWrite: Any = 0, cacheRead: Any = 0, totalTokens: Any? = nil
    ) -> [String: Any] {
        var value: [String: Any] = [
            "input": input,
            "output": output,
            "cacheWrite": cacheWrite,
            "cacheRead": cacheRead,
        ]
        if let reasoning { value["reasoning"] = reasoning }
        if let totalTokens { value["totalTokens"] = totalTokens }
        return value
    }

    private func message(
        id: String, role: String = "assistant",
        envelopeTimestamp: String = "2026-08-17T10:00:00.000Z",
        messageTimestamp: Double? = nil,
        stopReason: String? = nil,
        usage: [String: Any]
    ) -> [String: Any] {
        var nested: [String: Any] = [
            "role": role,
            "provider": "example",
            "model": "model-name",
            "content": [],
            "usage": usage,
        ]
        if let messageTimestamp { nested["timestamp"] = messageTimestamp }
        if let stopReason { nested["stopReason"] = stopReason }
        return [
            "type": "message",
            "id": id,
            "parentId": NSNull(),
            "timestamp": envelopeTimestamp,
            "message": nested,
        ]
    }

    @discardableResult
    private func write(
        _ objects: [[String: Any]], to root: URL? = nil,
        name: String = "session.jsonl", trailing: [String] = []
    ) throws -> URL {
        let lines = try objects.map {
            String(decoding: try JSONSerialization.data(withJSONObject: $0), as: UTF8.self)
        } + trailing
        let url = (root ?? rootA).appendingPathComponent(name)
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func parsed(_ url: URL) throws -> [LocalUsageReader.Entry] {
        try XCTUnwrap(LocalUsageReader.parsePiFile(url, fmt: LocalUsageReader.localDayFormatter()))
    }

    func testPiOutputAlreadyIncludesReasoningAndPrefersMessageTimestamp() throws {
        let actualDate = try XCTUnwrap(ISO8601Parser.date(from: "2026-08-16T23:59:59.000Z"))
        let url = try write([message(
            id: "turn-1",
            envelopeTimestamp: "2026-08-17T10:00:00.000Z",
            messageTimestamp: actualDate.timeIntervalSince1970 * 1_000,
            usage: usage(input: 10, output: 20, reasoning: 5, cacheWrite: 4,
                         cacheRead: 30, totalTokens: 64))])

        let entry = try XCTUnwrap(parsed(url).first)
        XCTAssertEqual(entry.id, "turn-1")
        XCTAssertEqual(entry.model, "pi")
        XCTAssertEqual(entry.input, 10)
        XCTAssertEqual(entry.output, 20, "Pi reasoning is a subset of output")
        XCTAssertEqual(entry.cacheWrite, 4)
        XCTAssertEqual(entry.cacheRead, 30)
        XCTAssertEqual(entry.total, 64, "Pi totalTokens already includes reasoning through output")
        XCTAssertEqual(entry.date.timeIntervalSince1970, actualDate.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(entry.localDay, LocalUsageReader.localDayFormatter().string(from: actualDate))
    }

    func testDirectMessageCompactionAndBranchSummaryUsageOnly() throws {
        let retained = message(id: "copied", usage: usage(input: 1_000))
        let compaction: [String: Any] = [
            "type": "compaction", "id": "compact", "parentId": "assistant",
            "timestamp": "2026-08-17T10:00:02.000Z", "usage": usage(input: 3),
            "retainedTail": [retained["message"]!],
        ]
        let branchSummary: [String: Any] = [
            "type": "branch_summary", "id": "summary", "parentId": "compact",
            "timestamp": "2026-08-17T10:00:03.000Z", "usage": usage(output: 4),
        ]
        let url = try write([
            message(id: "assistant", usage: usage(input: 1)),
            message(id: "tool-result", role: "toolResult", usage: usage(output: 2)),
            compaction,
            branchSummary,
        ])

        let entries = try parsed(url)
        XCTAssertEqual(Set(entries.map(\.id)), ["assistant", "tool-result", "compact", "summary"])
        XCTAssertEqual(entries.map(\.total).reduce(0, +), 10)
        XCTAssertFalse(entries.contains { $0.id == "copied" }, "retainedTail is copied context, not new usage")
    }

    func testPiSkipsAbortedAndErroredMessages() throws {
        let url = try write([
            message(id: "aborted", stopReason: "aborted", usage: usage(input: 10)),
            message(id: "errored", stopReason: "error", usage: usage(input: 20)),
            message(id: "complete", stopReason: "stop", usage: usage(input: 30)),
        ])

        XCTAssertEqual(try parsed(url).map(\.id), ["complete"])
    }

    func testFallbackMalformedAndPartialRecordsAreSafe() throws {
        let totalOnly = [
            "type": "message", "id": "total-only", "parentId": NSNull(),
            "timestamp": "2026-08-17T10:00:00.000Z",
            "message": ["role": "assistant", "usage": ["totalTokens": 77]],
        ] as [String: Any]
        let nullGranular = [
            "type": "message", "id": "null-fields", "parentId": NSNull(),
            "timestamp": "2026-08-17T10:00:00.000Z",
            "message": ["role": "assistant", "usage": [
                "input": NSNull(), "output": "not-a-number", "totalTokens": 88,
            ]],
        ] as [String: Any]
        let negative = message(id: "negative", usage: usage(input: -5, totalTokens: 99))
        let url = try write(
            [totalOnly, nullGranular, negative, ["type": "message", "id": "no-usage"]],
            trailing: ["{\"type\":\"message\",\"id\":"])

        let byID = Dictionary(uniqueKeysWithValues: try parsed(url).map { ($0.id, $0) })
        XCTAssertEqual(byID["total-only"]?.total, 77)
        XCTAssertEqual(byID["null-fields"]?.total, 88)
        XCTAssertEqual(byID["negative"]?.total, 0, "negative numeric fields clamp to zero, not fallback")
        XCTAssertEqual(byID.count, 3)
    }

    func testOversizedFieldsClampWithoutDoubleCountingReasoning() throws {
        let url = try write([message(
            id: "huge",
            usage: usage(input: 1e30, output: 1e30, reasoning: 1e30,
                         cacheWrite: 1e30, cacheRead: 1e30))])

        let entry = try XCTUnwrap(parsed(url).first)
        let max = LocalUsageReader.maxParsedTokenValue
        XCTAssertEqual(entry.input, max)
        XCTAssertEqual(entry.output, max)
        XCTAssertEqual(entry.cacheWrite, max)
        XCTAssertEqual(entry.cacheRead, max)
        XCTAssertEqual(entry.total, max * 4)
    }

    func testGlobalEnvelopeIDDedupRemovesForkCopiesButKeepsUniqueBranches() throws {
        let shared = message(id: "shared", usage: usage(input: 10))
        try write([shared, message(id: "branch-a", usage: usage(input: 20))], to: rootA)
        try write([shared, message(id: "branch-b", usage: usage(input: 30))], to: rootB)

        let entries = LocalUsageReader.piEntries(modifiedSince: .distantPast, roots: [rootA, rootB])
        XCTAssertEqual(Set(entries.map(\.id)), ["shared", "branch-a", "branch-b"])
        XCTAssertEqual(entries.map(\.total).reduce(0, +), 60)
    }

    func testPiSessionRootsCoverDefaultAndOverridesAndRemoveOverlap() throws {
        let home = base.appendingPathComponent("home")
        let agent = base.appendingPathComponent("custom-agent")
        let sessions = base.appendingPathComponent("custom-sessions")
        let roots = LocalUsageReader.computePiSessionRoots(
            agentDirValue: agent.path, sessionDirValue: sessions.path, home: home)

        XCTAssertEqual(Set(roots.map(\.path)), [
            home.appendingPathComponent(".pi/agent/sessions").path,
            agent.appendingPathComponent("sessions").path,
            sessions.path,
        ])

        let overlapping = LocalUsageReader.computePiSessionRoots(
            agentDirValue: home.appendingPathComponent(".pi/agent").path,
            sessionDirValue: home.appendingPathComponent(".pi/agent/sessions/project").path,
            home: home)
        XCTAssertEqual(overlapping.map(\.path), [home.appendingPathComponent(".pi/agent/sessions").path])
    }

    func testLocalPiProviderIdentityAndCostPolicy() {
        let provider = LocalPiProvider()
        XCTAssertEqual(provider.id, "pi")
        XCTAssertEqual(provider.displayName, "Pi")
        XCTAssertFalse(provider.reportsCost)
    }
}
