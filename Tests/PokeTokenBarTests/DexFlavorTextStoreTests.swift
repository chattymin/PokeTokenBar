import Foundation
import XCTest
@testable import PokeTokenBar

private struct OfflineLineProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

private enum FlavorTestError: Error { case unavailable }

private func flavorEntries(_ text: String, language: AppLanguage, label: String = "X",
                   degraded: Bool = false) -> DexEntries {
    DexEntries(entries: [DexFlavorText(versionKey: "x", versionID: 23, versionLabel: label, text: text)],
               language: language, isDegraded: degraded)
}

/// Holds every request until the test resumes it, so completion order is chosen by the test.
/// Like URLSession, a cancelled caller gets `CancellationError` — a store that let the page's
/// cancellation reach the request would lose it here.
private actor ControlledFlavorProvider: PokemonFlavorTextProviding {
    private var pending: [FlavorTextRequest: CheckedContinuation<DexEntries, Error>] = [:]
    private(set) var calls: [FlavorTextRequest] = []

    func flavorTexts(speciesID: Int, language: AppLanguage) async throws -> DexEntries {
        let request = FlavorTextRequest(speciesID: speciesID, language: language)
        calls.append(request)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    pending[request] = continuation
                }
            }
        } onCancel: {
            Task { await self.resume(request, with: .failure(CancellationError())) }
        }
    }

    func isPending(_ request: FlavorTextRequest) -> Bool { pending[request] != nil }

    func resume(_ request: FlavorTextRequest, with result: Result<DexEntries, Error>) {
        pending.removeValue(forKey: request)?.resume(with: result)
    }
}

@MainActor
final class DexFlavorTextStoreTests: XCTestCase {
    /// A Sendable constant: CI's Swift 6.1 runs the synchronous tearDown nonisolated (see defect-log).
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("flavor-store-\(UUID().uuidString)", isDirectory: true)

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeStore(_ provider: ControlledFlavorProvider, language: AppLanguage = .ko) -> CompanionStore {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("\(UUID().uuidString).json")
        let store = CompanionStore(provider: OfflineLineProvider(), flavorProvider: provider, fileURL: file)
        store.setLanguage(language)
        return store
    }

    /// Waits for the request to reach the provider; the language may only change after that point,
    /// otherwise the test cannot tell which language the request captured.
    private func waitUntilPending(_ provider: ControlledFlavorProvider, _ request: FlavorTextRequest,
                                  file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            if await provider.isPending(request) { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("request never reached the provider: \(request)", file: file, line: line)
    }

    private let ko = FlavorTextRequest(speciesID: 25, language: .ko)
    private let en = FlavorTextRequest(speciesID: 25, language: .en)

    // MARK: Landing guard

    func testStaleLanguageSuccessIsDroppedWhicheverResponseArrivesFirst() async {
        for staleFirst in [false, true] {
            let provider = ControlledFlavorProvider()
            let store = makeStore(provider)
            let koLoad = Task { await store.loadFlavorTexts(speciesID: 25) }
            await waitUntilPending(provider, ko)
            store.setLanguage(.en)
            let enLoad = Task { await store.loadFlavorTexts(speciesID: 25) }
            await waitUntilPending(provider, en)

            if staleFirst {
                await provider.resume(ko, with: .success(flavorEntries("한국어", language: .ko)))
                await koLoad.value
                await provider.resume(en, with: .success(flavorEntries("English", language: .en)))
                await enLoad.value
            } else {
                await provider.resume(en, with: .success(flavorEntries("English", language: .en)))
                await enLoad.value
                await provider.resume(ko, with: .success(flavorEntries("한국어", language: .ko)))
                await koLoad.value
            }

            let shown = store.flavorTextsByRequest[store.flavorTextRequest(speciesID: 25)]
            XCTAssertEqual(shown?.entries.first?.text, "English", "staleFirst=\(staleFirst)")
            XCTAssertNil(store.flavorTextsByRequest[ko], "a response for a language no longer selected must not be stored")
            XCTAssertFalse(store.isLoadingFlavorTexts(ko))
            XCTAssertFalse(store.isLoadingFlavorTexts(en))
        }
    }

    func testStaleLanguageFailureIsDropped() async {
        let provider = ControlledFlavorProvider()
        let store = makeStore(provider)
        let koLoad = Task { await store.loadFlavorTexts(speciesID: 25) }
        await waitUntilPending(provider, ko)
        store.setLanguage(.en)
        await provider.resume(ko, with: .failure(FlavorTestError.unavailable))
        await koLoad.value

        XCTAssertFalse(store.failedFlavorTextRequests.contains(ko))
        XCTAssertFalse(store.isLoadingFlavorTexts(ko))
    }

    // MARK: Language-keyed results

    func testEachLanguageKeepsItsOwnEntriesAcrossSwitches() async {
        let provider = ControlledFlavorProvider()
        let store = makeStore(provider)
        let koLoad = Task { await store.loadFlavorTexts(speciesID: 25) }
        await waitUntilPending(provider, ko)
        await provider.resume(ko, with: .success(flavorEntries("한국어", language: .ko)))
        await koLoad.value

        store.setLanguage(.en)
        let enLoad = Task { await store.loadFlavorTexts(speciesID: 25) }
        await waitUntilPending(provider, en)
        await provider.resume(en, with: .success(flavorEntries("English", language: .en)))
        await enLoad.value

        store.setLanguage(.ko)
        await store.loadFlavorTexts(speciesID: 25)

        let calls = await provider.calls
        XCTAssertEqual(calls, [ko, en], "returning to Korean reuses its entries; English was really requested")
        XCTAssertEqual(store.flavorTextsByRequest[store.flavorTextRequest(speciesID: 25)]?.entries.first?.text, "한국어")
        XCTAssertEqual(store.flavorTextsByRequest[en]?.entries.first?.text, "English")
    }

    // MARK: In-flight identity

    func testAnotherLanguageStartsItsOwnRequestWhileTheFirstIsPending() async {
        let provider = ControlledFlavorProvider()
        let store = makeStore(provider)
        let koLoad = Task { await store.loadFlavorTexts(speciesID: 25) }
        await waitUntilPending(provider, ko)
        store.setLanguage(.en)
        let enLoad = Task { await store.loadFlavorTexts(speciesID: 25) }
        await waitUntilPending(provider, en)

        XCTAssertTrue(store.isLoadingFlavorTexts(ko))
        XCTAssertTrue(store.isLoadingFlavorTexts(en))
        await provider.resume(en, with: .success(flavorEntries("English", language: .en)))
        await provider.resume(ko, with: .success(flavorEntries("한국어", language: .ko)))
        await enLoad.value
        await koLoad.value
    }

    /// Closing the detail page cancels its `.task`. Reopening right away must join the request the
    /// closed page started rather than skip it as "in flight" and wait on nothing.
    func testReopeningJoinsTheRequestTheClosedPageStarted() async {
        let provider = ControlledFlavorProvider()
        let store = makeStore(provider)
        let closedPage = Task { await store.loadFlavorTexts(speciesID: 25) }
        await waitUntilPending(provider, ko)
        closedPage.cancel()
        let reopenedPage = Task { await store.loadFlavorTexts(speciesID: 25) }
        for _ in 0..<20 { await Task.yield() }

        XCTAssertTrue(store.isLoadingFlavorTexts(ko))
        let stillPending = await provider.isPending(ko)
        XCTAssertTrue(stillPending, "the closed page's cancellation must not reach the request")
        await provider.resume(ko, with: .success(flavorEntries("한국어", language: .ko)))
        await reopenedPage.value
        await closedPage.value

        let calls = await provider.calls
        XCTAssertEqual(calls, [ko])
        XCTAssertEqual(store.flavorTextsByRequest[ko]?.entries.first?.text, "한국어")
        XCTAssertFalse(store.isLoadingFlavorTexts(ko))
        XCTAssertTrue(store.failedFlavorTextRequests.isEmpty)
    }

    // MARK: Degraded (REST) results

    func testDegradedEntriesStayThroughAFailedRefetchUntilARetrySucceeds() async {
        let provider = ControlledFlavorProvider()
        let store = makeStore(provider)
        let degraded = flavorEntries("한국어 설명", language: .ko, label: "X", degraded: true)

        let firstVisit = Task { await store.loadFlavorTexts(speciesID: 25) }
        await waitUntilPending(provider, ko)
        await provider.resume(ko, with: .success(degraded))
        await firstVisit.value
        XCTAssertEqual(store.flavorTextsByRequest[ko], degraded, "a degraded result is still shown")

        let reentry = Task { await store.loadFlavorTexts(speciesID: 25) }
        await waitUntilPending(provider, ko)
        XCTAssertEqual(store.flavorTextsByRequest[ko], degraded, "the refetch keeps the shown entries")
        await provider.resume(ko, with: .failure(FlavorTestError.unavailable))
        await reentry.value
        XCTAssertEqual(store.flavorTextsByRequest[ko], degraded)
        XCTAssertTrue(store.failedFlavorTextRequests.contains(ko))

        let retry = Task { await store.loadFlavorTexts(speciesID: 25) }
        await waitUntilPending(provider, ko)
        await provider.resume(ko, with: .success(flavorEntries("한국어 설명", language: .ko, label: "엑스")))
        await retry.value
        XCTAssertEqual(store.flavorTextsByRequest[ko]?.entries.first?.versionLabel, "엑스")
        XCTAssertFalse(store.flavorTextsByRequest[ko]?.isDegraded ?? true)
        XCTAssertFalse(store.failedFlavorTextRequests.contains(ko))

        await store.loadFlavorTexts(speciesID: 25)
        let calls = await provider.calls
        XCTAssertEqual(calls.count, 3, "a localized result is final; the next visit does not refetch")
    }
}
