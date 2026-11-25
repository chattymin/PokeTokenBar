import Foundation
import XCTest
@testable import PokeTokenBar

private final class PricingClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 1_800_000_000)
    func now() -> Date { lock.lock(); defer { lock.unlock() }; return value }
    func advance(_ seconds: TimeInterval) { lock.lock(); defer { lock.unlock() }; value.addTimeInterval(seconds) }
}

private actor PricingFetch {
    enum Failure: Error { case offline }
    private var data: Data?
    private var calls = 0
    init(_ data: Data?) { self.data = data }
    func set(_ data: Data?) { self.data = data }
    func count() -> Int { calls }
    func fetch(_ url: URL) async throws -> Data {
        calls += 1
        guard let data else { throw Failure.offline }
        return data
    }
}

final class ModelPricingRefreshTests: XCTestCase {
    private var valid: Data {
        Data(#"{"openai":{"id":"openai","models":{"gpt-example":{"id":"gpt-example","modalities":{"input":["text"],"output":["text"]},"cost":{"input":1,"output":5,"cache_read":0.1}}}},"anthropic":{"id":"anthropic","models":{"claude-example":{"id":"claude-example","modalities":{"input":["text"],"output":["text"]},"cost":{"input":1,"output":5,"cache_read":0.1}}}},"google":{"id":"google","models":{"gemini-example":{"id":"gemini-example","modalities":{"input":["text"],"output":["text"]},"cost":{"input":1,"output":5,"cache_read":0.1}}}}}"#.utf8)
    }
    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("PricingRefresh-\(UUID().uuidString)/cache.json")
    }
    private func remove(_ file: URL) { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    private func service(file: URL, clock: PricingClock, fetch: PricingFetch) -> ModelPricingRefresh {
        ModelPricingRefresh(fileURL: file, now: { clock.now() }, fetch: { try await fetch.fetch($0) })
    }

    func testSuccessPersistsAndRefreshesAfterOneDay() async throws {
        let file = tempFile(); defer { remove(file) }
        let clock = PricingClock(), fetch = PricingFetch(valid)
        let refresh = service(file: file, clock: clock, fetch: fetch)
        let first = await refresh.refreshIfNeeded()
        XCTAssertNotNil(first)
        let fresh = await refresh.refreshIfNeeded()
        XCTAssertNil(fresh)
        let restarted = service(file: file, clock: clock, fetch: fetch)
        let cached = await restarted.cachedCatalog()
        XCTAssertNotNil(cached)
        let notDue = await restarted.refreshIfNeeded()
        XCTAssertNil(notDue)
        var count = await fetch.count(); XCTAssertEqual(count, 1)
        clock.advance(24 * 60 * 60)
        let due = await restarted.refreshIfNeeded()
        XCTAssertNil(due, "identical prices renew the cache without triggering a usage refresh")
        count = await fetch.count(); XCTAssertEqual(count, 2)
    }

    func testInvalidAndOfflinePreserveCacheAndBackOffAcrossRestart() async throws {
        let file = tempFile(); defer { remove(file) }
        let clock = PricingClock(), fetch = PricingFetch(valid)
        let refresh = service(file: file, clock: clock, fetch: fetch)
        let first = await refresh.refreshIfNeeded(); XCTAssertNotNil(first)
        clock.advance(86_400)
        await fetch.set(Data(#"{"openai":{"id":"openai","models":{}}}"#.utf8))
        let invalid = await refresh.refreshIfNeeded(); XCTAssertNil(invalid)
        let afterInvalid = await refresh.cachedCatalog(); XCTAssertNotNil(afterInvalid)
        let restarted = service(file: file, clock: clock, fetch: fetch)
        let persisted = await restarted.cachedCatalog(); XCTAssertNotNil(persisted)
        let backedOff = await restarted.refreshIfNeeded(); XCTAssertNil(backedOff)
        var count = await fetch.count(); XCTAssertEqual(count, 2)
        clock.advance(3_600)
        await fetch.set(nil)
        let offline = await restarted.refreshIfNeeded(); XCTAssertNil(offline)
        let anotherRestart = service(file: file, clock: clock, fetch: fetch)
        let offlineCache = await anotherRestart.cachedCatalog(); XCTAssertNotNil(offlineCache)
        let offlineBackoff = await anotherRestart.refreshIfNeeded(); XCTAssertNil(offlineBackoff)
        count = await fetch.count(); XCTAssertEqual(count, 3)
    }

    func testOversizeAndCorruptCacheAreRejected() async throws {
        let file = tempFile(); defer { remove(file) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("corrupt".utf8).write(to: file)
        let clock = PricingClock(), fetch = PricingFetch(Data(repeating: 0, count: ModelPricingRefresh.maximumBytes + 1))
        let refresh = service(file: file, clock: clock, fetch: fetch)
        let cached = await refresh.cachedCatalog(); XCTAssertNil(cached)
        let result = await refresh.refreshIfNeeded(); XCTAssertNil(result)
        let after = await refresh.cachedCatalog(); XCTAssertNil(after)
    }

    func testCacheKeepsOnlyCatalogFields() async throws {
        let file = tempFile(); defer { remove(file) }
        let clock = PricingClock()
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        payload["unrelated-provider"] = ["metadata": String(repeating: "discard-me", count: 1000)]
        var openai = try XCTUnwrap(payload["openai"] as? [String: Any])
        openai["irrelevant-metadata"] = "discard-me"
        payload["openai"] = openai
        let full = try JSONSerialization.data(withJSONObject: payload)
        let fetch = PricingFetch(full)
        let refresh = service(file: file, clock: clock, fetch: fetch)
        let result = await refresh.refreshIfNeeded(); XCTAssertNotNil(result)
        let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        let encoded = try XCTUnwrap(envelope["data"] as? String)
        let compact = try XCTUnwrap(Data(base64Encoded: encoded))
        XCTAssertLessThan(compact.count, full.count)
        XCTAssertFalse(String(decoding: compact, as: UTF8.self).contains("discard-me"))
        XCTAssertEqual(try ModelPricingCatalog.decode(compact), try ModelPricingCatalog.decode(full))
    }

    func testConcurrentRefreshesShareOneFetch() async throws {
        let file = tempFile(); defer { remove(file) }
        let clock = PricingClock(), fetch = PricingFetch(valid)
        let refresh = service(file: file, clock: clock, fetch: fetch)
        async let a = refresh.refreshIfNeeded()
        async let b = refresh.refreshIfNeeded()
        let (first, second) = await (a, b)
        XCTAssertTrue(first != nil || second != nil)
        let count = await fetch.count(); XCTAssertEqual(count, 1)
        let cached = await refresh.cachedCatalog(); XCTAssertNotNil(cached)
    }
}
