import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import PokeTokenBar

private final class AnimationRecoveryURLProtocol: URLProtocol, @unchecked Sendable {
    enum Reply { case failure, gif(Data), pending }
    final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var replies: [Reply] = []
        private var urls: [URL] = []
        private var onStart: (@Sendable () -> Void)?

        func configure(_ replies: [Reply], onStart: (@Sendable () -> Void)? = nil) {
            lock.withLock { self.replies = replies; urls = []; self.onStart = onStart }
        }
        func receive(_ url: URL) -> Reply {
            let (reply, callback): (Reply, (@Sendable () -> Void)?) = lock.withLock {
                urls.append(url)
                return (replies.isEmpty ? .failure : replies.removeFirst(), onStart)
            }
            callback?()
            return reply
        }
        var requests: [URL] { lock.withLock { urls } }
    }
    static let state = State()
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "raw.githubusercontent.com" && request.url?.pathExtension == "gif"
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        switch Self.state.receive(url) {
        case .failure:
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        case let .gif(data):
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                           headerFields: ["Content-Type": "image/gif"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .pending: break   // URLSession cancellation must terminate this request.
        }
    }
    override func stopLoading() {}
}

/// No NSApplication, hosting view, or window: exercise the exact recovery path used by SpriteView
/// and the menu, including real URLSession errors, SpriteStore disk caching, and GIF decoding.
@MainActor
final class SpriteAnimationRecoveryTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AnimationRecoveryURLProtocol.state.configure([])
        URLProtocol.registerClass(AnimationRecoveryURLProtocol.self)
    }
    override func tearDown() {
        URLProtocol.unregisterClass(AnimationRecoveryURLProtocol.self)
        AnimationRecoveryURLProtocol.state.configure([])
        super.tearDown()
    }

    private func fixture() throws -> (directory: URL, gif: Data) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("animation-recovery-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        func pixels(_ red: CGFloat, _ green: CGFloat) throws -> CGImage {
            let context = try XCTUnwrap(CGContext(data: nil, width: 4, height: 4,
                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(red: red, green: green, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
            return try XCTUnwrap(context.makeImage())
        }
        let png = NSBitmapImageRep(cgImage: try pixels(0, 0))
        try XCTUnwrap(png.representation(using: .png, properties: [:]))
            .write(to: directory.appendingPathComponent("176-s.png"))
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, 2, nil))
        for (red, green) in [(CGFloat(1), CGFloat(0)), (CGFloat(0), CGFloat(1))] {
            CGImageDestinationAddImage(destination, try pixels(red, green),
                [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return (directory, data as Data)
    }

    func testInitialFailureKeepsFallbackThenRecoversTheSameSubject() async throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let store = SpriteStore(directory: fixture.directory)
        AnimationRecoveryURLProtocol.state.configure([.failure, .gif(fixture.gif)])
        let startedAt = ContinuousClock.now
        var fallback: NSImage?
        var fallbackCount = 0
        let frames = await SpriteLoader.recoveringAnimationFrames(
            speciesID: 176, shiny: false, store: store,
            onUnavailable: {
                fallbackCount += 1
                fallback = await SpriteLoader.image(speciesID: 176, store: store)
                XCTAssertNotNil(fallback, "the existing static image must remain available during retry")
            })
        XCTAssertGreaterThanOrEqual(startedAt.duration(to: .now), .seconds(2),
                                    "the production retry must wait instead of issuing a tight request loop")
        XCTAssertEqual(fallbackCount, 1)
        XCTAssertEqual(AnimationRecoveryURLProtocol.state.requests.count, 2)
        XCTAssertEqual(frames.count, 2, "one failed request must not end playback loading permanently")
        XCTAssertEqual(frames.map(\.delay), [0.1, 0.1])
        let image = try XCTUnwrap(frames.last?.image)
        let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil)))
        XCTAssertGreaterThan(bitmap.colorAt(x: 1, y: 1)?.greenComponent ?? 0, 0.9)
        XCTAssertNotNil(fallback)
    }

    func testRetrySeesGIFCachedByAnotherSurface() async throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        AnimationRecoveryURLProtocol.state.configure([.failure])
        let frames = await SpriteLoader.recoveringAnimationFrames(
            speciesID: 176, shiny: false, store: SpriteStore(directory: fixture.directory),
            waitBeforeRetry: { _ in
                try fixture.gif.write(to: fixture.directory.appendingPathComponent("176-a.gif"))
            }, onUnavailable: {})
        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(AnimationRecoveryURLProtocol.state.requests.count, 1,
                       "retry must reuse a GIF downloaded by a later popover visit")
    }

    func testRepeatedFailuresBackOffWithoutAnAttemptLimit() async throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        var waits: [Duration] = []
        var fallbackCount = 0
        var result: [(image: NSImage, delay: TimeInterval)] = []
        let task = Task<Void, Never> { @MainActor in
            result = await SpriteLoader.recoveringAnimationFrames(
                speciesID: 176, shiny: false, store: SpriteStore(directory: fixture.directory),
                waitBeforeRetry: { duration in
                    waits.append(duration)
                    if waits.count == 7 {
                        withUnsafeCurrentTask { $0?.cancel() }
                        try Task.checkCancellation()
                    }
                }, onUnavailable: { fallbackCount += 1 })
        }
        await task.value
        XCTAssertEqual(waits, [2, 4, 8, 16, 30, 30, 30].map { .seconds($0) })
        XCTAssertEqual(AnimationRecoveryURLProtocol.state.requests.count, 7)
        XCTAssertEqual(fallbackCount, 1, "retrying GIFs must not repeatedly replace the static fallback")
        XCTAssertTrue(result.isEmpty)
    }

    func testCancellationInterruptsTheProductionBackoff() async throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let fallbackShown = expectation(description: "fallback shown before sleeping")
        var result: [(image: NSImage, delay: TimeInterval)] = []
        let task = Task<Void, Never> { @MainActor in
            result = await SpriteLoader.recoveringAnimationFrames(
                speciesID: 176, shiny: false, store: SpriteStore(directory: fixture.directory),
                onUnavailable: { fallbackShown.fulfill() })
        }
        await fulfillment(of: [fallbackShown], timeout: 2)
        let cancelledAt = ContinuousClock.now
        task.cancel()   // Same cancellation propagated by .task teardown/species/low-power changes.
        await task.value
        XCTAssertLessThan(cancelledAt.duration(to: .now), .seconds(1))
        XCTAssertTrue(result.isEmpty)
        XCTAssertEqual(AnimationRecoveryURLProtocol.state.requests.count, 1)
    }

    func testCancelledShinyRequestDoesNotStartNormalFallbackOrApplyAResult() async throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let requestStarted = expectation(description: "shiny GIF request started")
        AnimationRecoveryURLProtocol.state.configure([.pending], onStart: { requestStarted.fulfill() })
        var fallbackCount = 0
        var result: [(image: NSImage, delay: TimeInterval)] = []
        let task = Task<Void, Never> { @MainActor in
            result = await SpriteLoader.recoveringAnimationFrames(
                speciesID: 176, shiny: true, store: SpriteStore(directory: fixture.directory),
                onUnavailable: { fallbackCount += 1 })
        }
        await fulfillment(of: [requestStarted], timeout: 2)
        task.cancel()
        await task.value
        XCTAssertEqual(AnimationRecoveryURLProtocol.state.requests.map(\.lastPathComponent), ["176.gif"])
        XCTAssertTrue(AnimationRecoveryURLProtocol.state.requests.first?.path.contains("/shiny/") == true)
        XCTAssertEqual(fallbackCount, 0)
        XCTAssertTrue(result.isEmpty)
    }

    func testUnsupportedSpeciesLoadsStaticOnceWithoutRetry() async throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try FileManager.default.copyItem(at: fixture.directory.appendingPathComponent("176-s.png"),
                                        to: fixture.directory.appendingPathComponent("1000-s.png"))
        let store = SpriteStore(directory: fixture.directory)
        var fallback: NSImage?
        let frames = await SpriteLoader.recoveringAnimationFrames(
            speciesID: 1000, shiny: false, store: store,
            waitBeforeRetry: { _ in XCTFail("a species without GIF support must not retry") },
            onUnavailable: { fallback = await SpriteLoader.image(speciesID: 1000, store: store) })
        XCTAssertTrue(frames.isEmpty)
        XCTAssertNotNil(fallback)
        XCTAssertTrue(AnimationRecoveryURLProtocol.state.requests.isEmpty)
    }

    func testAlreadyCancelledLoadDoesNotRequestOrApplyFallback() async throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let task = Task<Void, Never> { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            let frames = await SpriteLoader.recoveringAnimationFrames(
                speciesID: 176, shiny: false, store: SpriteStore(directory: fixture.directory),
                onUnavailable: { XCTFail("cancelled views must not apply a fallback") })
            XCTAssertTrue(frames.isEmpty)
        }
        await task.value
        XCTAssertTrue(AnimationRecoveryURLProtocol.state.requests.isEmpty)
    }

    func testCancellationWhileApplyingFallbackDoesNotScheduleRetry() async throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let task = Task<Void, Never> { @MainActor in
            let frames = await SpriteLoader.recoveringAnimationFrames(
                speciesID: 176, shiny: false, store: SpriteStore(directory: fixture.directory),
                waitBeforeRetry: { _ in XCTFail("cancelled fallback must not schedule another request") },
                onUnavailable: { withUnsafeCurrentTask { $0?.cancel() } })
            XCTAssertTrue(frames.isEmpty)
        }
        await task.value
        XCTAssertEqual(AnimationRecoveryURLProtocol.state.requests.count, 1)
    }

    func testShinyMissStillUsesNormalGIFWithoutWaiting() async throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        AnimationRecoveryURLProtocol.state.configure([.failure, .gif(fixture.gif)])
        let frames = await SpriteLoader.recoveringAnimationFrames(
            speciesID: 176, shiny: true, store: SpriteStore(directory: fixture.directory),
            waitBeforeRetry: { _ in XCTFail("normal GIF fallback is part of the first load attempt") },
            onUnavailable: { XCTFail("a normal GIF fallback needs no static placeholder") })
        XCTAssertEqual(frames.count, 2)
        let paths = AnimationRecoveryURLProtocol.state.requests.map(\.path)
        XCTAssertEqual(paths.count, 2)
        XCTAssertTrue(paths.first?.contains("/shiny/") == true)
        XCTAssertFalse(paths.last?.contains("/shiny/") == true)
    }

    func testWarmShinyFormCacheSkipsFallbackNetworkAndBackoff() async throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try fixture.gif.write(to: fixture.directory.appendingPathComponent("201-b-sha.gif"))
        let frames = await SpriteLoader.recoveringAnimationFrames(
            speciesID: 201, shiny: true, store: SpriteStore(directory: fixture.directory), form: .b,
            waitBeforeRetry: { _ in XCTFail("a warm GIF must start immediately") },
            onUnavailable: { XCTFail("a warm GIF needs no static fallback") })
        XCTAssertEqual(frames.count, 2)
        XCTAssertTrue(AnimationRecoveryURLProtocol.state.requests.isEmpty)
    }
}
