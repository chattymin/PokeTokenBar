import XCTest
import AppKit
import SwiftUI
import Observation
@testable import PokeTokenBar

private actor UnownSpriteLoadGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false

    func wait() async {
        if released { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class UnownSpriteSubjectBox {
    var subject: SpriteSubject
    var sawCancellation = false
    init(_ subject: SpriteSubject) { self.subject = subject }
}

@MainActor
@Observable
private final class UnownSpriteSelection {
    var shiny = false
}

@MainActor
private struct UnownSpriteTogglePreview: View {
    let selection: UnownSpriteSelection
    let store: SpriteStore

    var body: some View {
        SpriteView(speciesID: 201, size: 64, shiny: selection.shiny, spriteStore: store, unownForm: .b)
    }
}

@MainActor
final class UnownSpriteViewTests: XCTestCase {
    func testStaticShinyToggleLoadsShinyWhenOnlyNormalImageIsCached() async throws {
        try await assertShinyLoaded(startingShiny: false)
    }

    func testStaticInitiallyShinyLoadsShinyWhenOnlyNormalImageIsCached() async throws {
        try await assertShinyLoaded(startingShiny: true)
    }

    private func assertShinyLoaded(startingShiny: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("unown-toggle-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        func png(_ color: NSColor) throws -> Data {
            let context = try XCTUnwrap(CGContext(data: nil, width: 4, height: 4,
                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(try XCTUnwrap(color.usingColorSpace(.deviceRGB)).cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
            let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(context.makeImage()))
            return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        }
        try png(.red).write(to: directory.appendingPathComponent("201-b-s.png"))
        let shinyFile = directory.appendingPathComponent("201-b-shs.png")
        let shinyBytes = try png(.blue)
        try shinyBytes.write(to: shinyFile)
        let spriteStore = SpriteStore(directory: directory)
        // Keep the async loader deterministic and offline, while the synchronous shiny cache misses.
        let warmed = await spriteStore.data(speciesID: 201, animated: false, shiny: true, unownForm: .b)
        XCTAssertEqual(warmed, shinyBytes)
        try FileManager.default.removeItem(at: shinyFile)
        let normal = try XCTUnwrap(SpriteLoader.cachedImage(speciesID: 201, directory: directory, unownForm: .b))
        XCTAssertTrue(SpriteLoader.cachedImage(speciesID: 201, shiny: true,
                                               directory: directory, unownForm: .b) === normal)

        _ = NSApplication.shared
        let selection = UnownSpriteSelection()
        selection.shiny = startingShiny
        let host = NSHostingController(rootView: UnownSpriteTogglePreview(selection: selection, store: spriteStore))
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 64, height: 64),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentViewController = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        host.view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))

        if !startingShiny { selection.shiny = true }
        let shinyKey = shinyFile.path as NSString
        for _ in 0..<40 {
            host.view.layoutSubtreeIfNeeded()
            if SpriteLoader.imageCache.object(forKey: shinyKey) != nil { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        let loaded = try XCTUnwrap(SpriteLoader.imageCache.object(forKey: shinyKey),
                                  "The static view must still request shiny bytes after seeding a normal fallback")
        XCTAssertFalse(loaded === normal)
        let pixels = NSBitmapImageRep(cgImage: try XCTUnwrap(loaded.cgImage(forProposedRect: nil, context: nil, hints: nil)))
        let color = try XCTUnwrap(pixels.colorAt(x: 2, y: 2)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(color.blueComponent, 0.9)
        XCTAssertLessThan(color.redComponent, 0.1)
    }

    func testAnimationIdentitiesSeparateAllLettersAndShinyVariants() {
        var viewIDs = Set<String>()
        var menuIDs = Set<String>()
        for form in UnownForm.allCases {
            for shiny in [false, true] {
                viewIDs.insert(SpriteView.frameTaskID(speciesID: 201, shiny: shiny, floor: 0.4,
                                                      unownForm: form))
                menuIDs.insert(AppDelegate.menuSpriteKey(id: 201, shiny: shiny, floor: 0.4,
                                                         unownForm: form))
            }
        }
        XCTAssertEqual(viewIDs.count, 56)
        XCTAssertEqual(menuIDs.count, 56)
    }

    func testAnimationIdentitiesNormalizeLegacyAAndIgnoreFormsForOtherSpecies() {
        XCTAssertEqual(SpriteView.frameTaskID(speciesID: 201, shiny: false, floor: 0.4),
                       SpriteView.frameTaskID(speciesID: 201, shiny: false, floor: 0.4, unownForm: .a))
        XCTAssertEqual(AppDelegate.menuSpriteKey(id: 201, shiny: false, floor: 0.4),
                       AppDelegate.menuSpriteKey(id: 201, shiny: false, floor: 0.4, unownForm: .a))
        XCTAssertEqual(SpriteView.frameTaskID(speciesID: 25, shiny: false, floor: 0.4),
                       SpriteView.frameTaskID(speciesID: 25, shiny: false, floor: 0.4, unownForm: .z))
        XCTAssertEqual(AppDelegate.menuSpriteKey(id: 25, shiny: false, floor: 0.4),
                       AppDelegate.menuSpriteKey(id: 25, shiny: false, floor: 0.4, unownForm: .z))
    }

    func testChangingUnownLetterReloadsEvenWhenSpeciesAndShinyMatch() {
        for previous in UnownForm.allCases {
            for next in UnownForm.allCases {
                XCTAssertEqual(
                    SpriteView.needsReload(loadedID: 201, loadedShiny: false, id: 201, shiny: false,
                                           loadedUnownForm: previous, unownForm: next),
                    previous != next,
                    "Changing \(previous.symbol) to \(next.symbol) must display the correct letter")
            }
        }
    }

    func testLegacyUnownFormUsesTheSameSpriteAsExplicitA() {
        XCTAssertFalse(SpriteView.needsReload(loadedID: 201, loadedShiny: false, id: 201, shiny: false,
                                             loadedUnownForm: nil, unownForm: .a))
        XCTAssertFalse(SpriteView.needsReload(loadedID: 201, loadedShiny: false, id: 201, shiny: false,
                                             loadedUnownForm: .a, unownForm: nil))
        XCTAssertTrue(SpriteView.needsReload(loadedID: 201, loadedShiny: false, id: 201, shiny: false,
                                            loadedUnownForm: nil, unownForm: .question))
    }

    func testSameUnownLetterStillReloadsOnShinyToggle() {
        XCTAssertTrue(SpriteView.needsReload(loadedID: 201, loadedShiny: false, id: 201, shiny: true,
                                            loadedUnownForm: .exclamation, unownForm: .exclamation))
        XCTAssertFalse(SpriteView.needsReload(loadedID: 201, loadedShiny: true, id: 201, shiny: true,
                                             loadedUnownForm: .question, unownForm: .question))
    }

    func testUnownFormDoesNotAffectOtherSpeciesSprites() {
        XCTAssertFalse(SpriteView.needsReload(loadedID: 25, loadedShiny: false, id: 25, shiny: false,
                                             loadedUnownForm: .a, unownForm: .z))
        XCTAssertTrue(SpriteView.needsReload(loadedID: 201, loadedShiny: false, id: 25, shiny: false,
                                            loadedUnownForm: .a, unownForm: nil))
    }

    func testCachedAToBToAReturnsToAWhileBLoadIsPending() async {
        await assertCachedRoundTrip(intermediateForm: .b, intermediateShiny: false)
    }

    func testCachedNormalToShinyToNormalReturnsToNormalWhileShinyLoadIsPending() async {
        await assertCachedRoundTrip(intermediateForm: .a, intermediateShiny: true)
    }

    /// 실제 await 구간을 게이트로 유지한다. 중간 캐시 이미지를 표시한 뒤 첫 모습으로 돌아가고,
    /// 취소된 중간 로드가 늦게 끝나도 이미지·폼·이로치가 함께 첫 모습으로 남아야 한다.
    private func assertCachedRoundTrip(intermediateForm: UnownForm, intermediateShiny: Bool,
                                       file: StaticString = #filePath, line: UInt = #line) async {
        let original = NSImage(size: NSSize(width: 4, height: 4))
        let intermediate = NSImage(size: NSSize(width: 8, height: 8))
        let box = UnownSpriteSubjectBox(SpriteSubject(image: original, loadedID: 201,
                                                       loadedShiny: false, loadedUnownForm: .a))
        let gate = UnownSpriteLoadGate()
        let (started, startSignal) = AsyncStream<Void>.makeStream()
        let pendingLoad = Task { @MainActor in
            box.subject = box.subject.startingLoad(cachedImage: intermediate, for: 201,
                                                   shiny: intermediateShiny, unownForm: intermediateForm)
            startSignal.yield(())
            startSignal.finish()
            await gate.wait()
            box.sawCancellation = Task.isCancelled
            if let next = box.subject.applyingLoad(intermediate, for: 201, cancelled: Task.isCancelled,
                                                   shiny: intermediateShiny, unownForm: intermediateForm) {
                box.subject = next
            }
        }
        for await _ in started {}
        XCTAssertTrue(box.subject.image === intermediate, file: file, line: line)
        XCTAssertEqual(box.subject.loadedUnownForm, intermediateForm, file: file, line: line)
        XCTAssertEqual(box.subject.loadedShiny, intermediateShiny, file: file, line: line)

        pendingLoad.cancel()
        let needsOriginal = SpriteView.needsReload(loadedID: box.subject.loadedID,
                                                   loadedShiny: box.subject.loadedShiny, id: 201, shiny: false,
                                                   loadedUnownForm: box.subject.loadedUnownForm, unownForm: .a)
        XCTAssertTrue(needsOriginal, "The intermediate cache must not be mistaken for the original sprite",
                      file: file, line: line)
        if needsOriginal {
            box.subject = box.subject.startingLoad(cachedImage: original, for: 201, shiny: false, unownForm: .a)
        }
        await gate.release()
        await pendingLoad.value

        XCTAssertTrue(box.sawCancellation, file: file, line: line)
        XCTAssertTrue(box.subject.image === original, file: file, line: line)
        XCTAssertEqual(box.subject.loadedUnownForm, .a, file: file, line: line)
        XCTAssertFalse(box.subject.loadedShiny, file: file, line: line)
    }
}
