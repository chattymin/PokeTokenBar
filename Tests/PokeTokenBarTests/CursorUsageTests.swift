import XCTest
@testable import PokeTokenBar

final class CursorUsageTests: XCTestCase {

    // MARK: - Bubble parsing

    func testParseCursorBubbleWithTokens() {
        let now = Date()
        let bubble: [String: Any] = [
            "type": 1,
            "modelType": "claude-3.5-sonnet",
            "createdAt": ISO8601DateFormatter().string(from: now),
            "tokenCount": [
                "inputTokens": 1500,
                "outputTokens": 800,
            ] as [String: Any],
        ]
        let entry = LocalAdditionalUsageReader.parseCursorBubble(
            bubble, key: "bubbleId:tab1:msg1", modifiedSince: .distantPast)
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.input, 1500)
        XCTAssertEqual(entry?.output, 800)
        XCTAssertEqual(entry?.model, "claude-3.5-sonnet")
        XCTAssertTrue(entry?.id.hasPrefix("cursor|") ?? false)
    }

    func testParseCursorBubbleWithFractionalSeconds() {
        let bubble: [String: Any] = [
            "tokenCount": ["inputTokens": 100, "outputTokens": 50] as [String: Any],
            "createdAt": "2026-01-04T10:34:54.766Z",
            "modelType": "gpt-4o",
        ]
        let entry = LocalAdditionalUsageReader.parseCursorBubble(
            bubble, key: "bubbleId:t:m", modifiedSince: .distantPast)
        XCTAssertNotNil(entry, "ISO 8601 with fractional seconds should parse")
        XCTAssertEqual(entry?.input, 100)
        XCTAssertEqual(entry?.output, 50)
        XCTAssertEqual(entry?.model, "gpt-4o")
    }

    func testParseCursorBubbleIgnoresZeroTokens() {
        let bubble: [String: Any] = [
            "tokenCount": ["inputTokens": 0, "outputTokens": 0] as [String: Any],
            "createdAt": ISO8601DateFormatter().string(from: Date()),
        ]
        let entry = LocalAdditionalUsageReader.parseCursorBubble(
            bubble, key: "bubbleId:t:m", modifiedSince: .distantPast)
        XCTAssertNil(entry, "Zero-token entries should be skipped")
    }

    func testParseCursorBubbleIgnoresOldEntries() {
        let yesterday = Date().addingTimeInterval(-86400)
        let bubble: [String: Any] = [
            "tokenCount": ["inputTokens": 100, "outputTokens": 50] as [String: Any],
            "createdAt": ISO8601DateFormatter().string(from: yesterday),
        ]
        let entry = LocalAdditionalUsageReader.parseCursorBubble(
            bubble, key: "bubbleId:t:m", modifiedSince: Date())
        XCTAssertNil(entry, "Entries before modifiedSince should be skipped")
    }

    func testParseCursorBubbleMissingTokenCount() {
        let bubble: [String: Any] = [
            "type": 1,
            "modelType": "gpt-4",
            "createdAt": ISO8601DateFormatter().string(from: Date()),
        ]
        let entry = LocalAdditionalUsageReader.parseCursorBubble(
            bubble, key: "bubbleId:t:m", modifiedSince: .distantPast)
        XCTAssertNil(entry, "Missing tokenCount should be skipped")
    }

    func testParseCursorBubbleMissingModelFallsBackToUnknown() {
        let bubble: [String: Any] = [
            "tokenCount": ["inputTokens": 100, "outputTokens": 50] as [String: Any],
            "createdAt": ISO8601DateFormatter().string(from: Date()),
        ]
        let entry = LocalAdditionalUsageReader.parseCursorBubble(
            bubble, key: "bubbleId:t:m", modifiedSince: .distantPast)
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.model, "unknown")
    }

    func testParseCursorBubbleMissingCreatedAt() {
        let bubble: [String: Any] = [
            "tokenCount": ["inputTokens": 100, "outputTokens": 50] as [String: Any],
        ]
        let entry = LocalAdditionalUsageReader.parseCursorBubble(
            bubble, key: "bubbleId:t:m", modifiedSince: .distantPast)
        XCTAssertNil(entry, "Missing createdAt should be skipped")
    }

    func testParseCursorBubbleInvalidCreatedAt() {
        let bubble: [String: Any] = [
            "tokenCount": ["inputTokens": 100, "outputTokens": 50] as [String: Any],
            "createdAt": "not-a-date",
        ]
        let entry = LocalAdditionalUsageReader.parseCursorBubble(
            bubble, key: "bubbleId:t:m", modifiedSince: .distantPast)
        XCTAssertNil(entry, "Invalid createdAt should be skipped")
    }

    func testParseCursorBubbleIdPrefix() {
        let bubble: [String: Any] = [
            "tokenCount": ["inputTokens": 100, "outputTokens": 50] as [String: Any],
            "createdAt": ISO8601DateFormatter().string(from: Date()),
        ]
        let entry = LocalAdditionalUsageReader.parseCursorBubble(
            bubble, key: "bubbleId:abc:def", modifiedSince: .distantPast)
        XCTAssertEqual(entry?.id, "cursor|bubbleId:abc:def")
    }

    // MARK: - cursorEntries with nonexistent path

    func testCursorEntriesNonexistentPath() {
        let entries = LocalAdditionalUsageReader.cursorEntries(
            modifiedSince: .distantPast,
            roots: [URL(fileURLWithPath: "/nonexistent/cursor/path")])
        XCTAssertTrue(entries.isEmpty, "Nonexistent database should return empty")
    }

    // MARK: - Provider identity

    func testLocalCursorProviderID() {
        let provider = LocalCursorProvider()
        XCTAssertEqual(provider.id, "cursor")
        XCTAssertEqual(provider.displayName, "Cursor")
    }
}
