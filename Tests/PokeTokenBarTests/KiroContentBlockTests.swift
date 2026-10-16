import XCTest
@testable import PokeTokenBar

/// CLI 2.25.0 content-block shapes observed in local writer output, with synthetic values only.
final class KiroContentBlockTests: XCTestCase {
    private typealias Object = [String: Any]
    private var root: URL!
    private var file: URL { root.appendingPathComponent("cli/synthetic.jsonl") }
    private let timestamp = 1_770_983_426.0

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("kiro-blocks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("cli"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    func testNestedToolResultsCountTextAndJSONOnce() throws {
        let results = [block("toolResult", [
            "toolUseId": "tool-1", "status": "success", "content": [
                block("text", String(repeating: "r", count: 800)),
                block("json", ["stdout": "가나ab", "nested": ["more", 12, NSNull()]]),
            ],
        ])]
        var event = message("ToolResults", results)
        var data = try XCTUnwrap(event["data"] as? Object)
        // The writer also stores execution bookkeeping in results; do not count both copies.
        data["results"] = ["tool-1": ["result": ["Success": ["items": String(repeating: "duplicate", count: 100)]]]]
        event["data"] = data
        try write([prompt(), message("AssistantMessage", [block("text", "done")]), event])
        let entry = try XCTUnwrap(entries().first)
        // Keep the existing JSON-value estimator: UTF-8 strings 8 + 4, number 2, null 0.
        XCTAssertEqual(entry.input, (4 + 800 + 14) / 4)
        XCTAssertEqual(entry.output, 1)
        XCTAssertNil(entry.explicitCost)
    }

    func testToolArgumentsAndThinkingCountButMetadataAndImagesDoNot() throws {
        let opaque = String(repeating: "x", count: 1_024)
        let image = block("image", ["format": "png", "source": ["bytes": opaque]])
        try write([
            prompt(extra: [image]),
            message("AssistantMessage", [
                block("thinking", ["text": "think think!", "signature": opaque,
                                   "redactedContent": [opaque], "modelId": "model", "toolsDigest": opaque]),
                block("toolUse", ["name": opaque, "toolUseId": opaque,
                                  "input": ["path": "file", "content": "abcd"]]),
                block("text", "done"),
            ]),
            message("ToolResults", [block("toolResult", ["content": [image]])]),
        ])
        let entry = try XCTUnwrap(entries().first)
        XCTAssertEqual(entry.input, 1)
        XCTAssertEqual(entry.output, (12 + 8 + 4) / 4)
    }

    func testToolOnlyResponseDoesNotDisappear() throws {
        try write([prompt(text: ""), message("AssistantMessage", [
            block("toolUse", ["name": "test_tool", "toolUseId": "tool-1", "input": ["command": "abcd"]]),
        ])])
        let entry = try XCTUnwrap(entries().first)
        XCTAssertEqual(entry.input, 0)
        XCTAssertEqual(entry.output, 1)
    }

    func testToolContentAccumulatesAcrossDaysAndClearResetsHistory() throws {
        try write([
            prompt(),
            message("AssistantMessage", [block("thinking", ["text": "plan"]),
                block("toolUse", ["input": ["path": "file", "content": "abcd"]]), block("text", "done")]),
            message("ToolResults", [block("toolResult", ["content": [
                block("text", "abcdefgh"), block("json", ["stdout": "ijklmnop"]),
            ]])]),
            prompt(at: timestamp + 86_400), message("AssistantMessage", [block("text", "done")]),
            message("Clear", []),
            prompt(at: timestamp + 86_500), message("AssistantMessage", [block("text", "done")]),
        ])
        let all = entries()
        XCTAssertEqual(all.map(\.input), [5, 10, 1])
        XCTAssertEqual(all.map(\.output), [4, 1, 1])
        let recent = entries(since: Date(timeIntervalSince1970: timestamp + 86_400))
        XCTAssertEqual(recent.map(\.id), Array(all.dropFirst()).map(\.id))
        XCTAssertEqual(recent.map(\.input), [10, 1], "Out-of-window tool history is still resent")
        let day = try XCTUnwrap(recent.first?.localDay)
        XCTAssertEqual(LocalUsageReader.daily(entries: recent, localDay: day)?.totalTokens, 13)
    }

    func testLateToolResultUpdatesSameEntryWithoutDoubleCounting() throws {
        try write([prompt(), message("AssistantMessage", [block("text", "done")])])
        let first = LocalAdditionalUsageReader.kiroEntries(
            modifiedSince: .distantPast, knownSignatures: [:], roots: [root])
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: jsonLine(message("ToolResults", [
            block("toolResult", ["content": [block("text", "abcdefghijklmnop")]]),
        ])))
        try handle.close()
        let updated = LocalAdditionalUsageReader.kiroEntries(
            modifiedSince: .distantPast, knownSignatures: first.signatures, roots: [root])
        XCTAssertEqual(updated.entries.map(\.id), first.entries.map(\.id))
        let merged = LocalUsageReader.dedupKeepMax(first.entries + updated.entries)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.input, 5)
        XCTAssertEqual(merged.first?.output, 1)
        let unchanged = LocalAdditionalUsageReader.kiroEntries(
            modifiedSince: .distantPast, knownSignatures: updated.signatures, roots: [root])
        XCTAssertTrue(unchanged.entries.isEmpty)
    }

    func testMissingAndUnknownBlockPayloadsDoNotInventContent() throws {
        try write([prompt(), message("AssistantMessage", [
            block("toolUse", [:]), block("thinking", ["signature": "opaque"]),
            block("thinking", NSNull()), block("unsupported", ["text": "do not count"]),
            block("text", "done"),
        ]), message("ToolResults", [block("toolResult", [:]), block("toolResult", ["content": [
            ["kind": "json"], block("json", NSNull()),
        ]])])])
        let entry = try XCTUnwrap(entries().first)
        XCTAssertEqual(entry.input, 1)
        XCTAssertEqual(entry.output, 1)
    }

    private func block(_ kind: String, _ data: Any) -> Object { ["kind": kind, "data": data] }

    private func message(_ kind: String, _ content: [Object]) -> Object {
        ["version": "v1", "kind": kind, "data": ["content": content]]
    }

    private func prompt(text: String = "abcd", at: Double? = nil, extra: [Object] = []) -> Object {
        ["version": "v1", "kind": "Prompt", "data": [
            "content": [block("text", text)] + extra, "meta": ["timestamp": at ?? timestamp],
        ]]
    }

    private func jsonLine(_ object: Object) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        data.append(0x0a)
        return data
    }

    private func write(_ events: [Object]) throws {
        let data = try events.reduce(into: Data()) { $0.append(try jsonLine($1)) }
        try data.write(to: file)
    }

    private func entries(since: Date = .distantPast) -> [LocalUsageReader.Entry] {
        LocalAdditionalUsageReader.kiroEntries(modifiedSince: since, roots: [root]).sorted { $0.date < $1.date }
    }
}
