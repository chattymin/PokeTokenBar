import AppKit
import XCTest
@testable import PokeTokenBar

/// Exercise the production loaders with generated pixels and an isolated disk cache.
/// Reusing raw Data alone does not prevent View.init from reopening files and creating NSImages.
@MainActor
final class SpriteImageCacheTests: XCTestCase {
    func testSynchronousLoadsReuseImagesAndKeepVariantsSeparate() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sprite-cache-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 6, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.bitmapData?.initialize(repeating: 255, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        var loaded: [NSImage] = []

        for (filename, animated, shiny) in [
            ("25-s.png", false, false), ("25-shs.png", false, true),
            ("25-a.gif", true, false), ("25-sha.gif", true, true),
        ] {
            let file = dir.appendingPathComponent(filename)
            try XCTUnwrap(bitmap.representation(using: animated ? .gif : .png, properties: [:])).write(to: file)
            let first = try XCTUnwrap(SpriteLoader.cachedImage(
                speciesID: 25, animated: animated, shiny: shiny, directory: dir))
            XCTAssertFalse(loaded.contains { $0 === first }, "normal/shiny and PNG/GIF must have distinct entries")
            loaded.append(first)
            try FileManager.default.removeItem(at: file)
            XCTAssertTrue(SpriteLoader.cachedImage(
                speciesID: 25, animated: animated, shiny: shiny, directory: dir) === first,
                "a warm lookup must reuse the image object without reopening its file")
        }

        let otherDir = dir.appendingPathComponent("other")
        try FileManager.default.createDirectory(at: otherDir, withIntermediateDirectories: true)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            .write(to: otherDir.appendingPathComponent("25-s.png"))
        let other = try XCTUnwrap(SpriteLoader.cachedImage(speciesID: 25, directory: otherDir))
        XCTAssertFalse(other === loaded[0], "an injected directory must not reuse another directory's pixels")
    }

    func testMissingOrInvalidImageDoesNotPreventALaterLoad() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sprite-retry-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("25-s.png")
        XCTAssertNil(SpriteLoader.cachedImage(speciesID: 25, directory: dir))
        try Data("invalid image".utf8).write(to: file)
        XCTAssertNil(SpriteLoader.cachedImage(speciesID: 25, directory: dir))

        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.bitmapData?.initialize(repeating: 255, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: file)
        XCTAssertNotNil(SpriteLoader.cachedImage(speciesID: 25, directory: dir),
                        "an earlier cache miss or decode failure must not be memoized")
    }

    func testNormalFallbackDoesNotMaskALaterShinyImage() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sprite-shiny-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.bitmapData?.initialize(repeating: 255, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: dir.appendingPathComponent("25-s.png"))
        let normal = try XCTUnwrap(SpriteLoader.cachedImage(speciesID: 25, directory: dir))
        XCTAssertTrue(SpriteLoader.cachedImage(speciesID: 25, shiny: true, directory: dir) === normal)

        try png.write(to: dir.appendingPathComponent("25-shs.png"))
        let shiny = try XCTUnwrap(SpriteLoader.cachedImage(speciesID: 25, shiny: true, directory: dir))
        XCTAssertFalse(shiny === normal, "fallback pixels must not be stored under the shiny key")
        XCTAssertTrue(SpriteLoader.cachedImage(speciesID: 25, directory: dir) === normal)
    }

    func testAsyncLoadsPopulateTheSynchronousCacheAndReuseEachOther() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sprite-async-\(UUID().uuidString)")
        let store = SpriteStore(directory: dir)
        defer { try? FileManager.default.removeItem(at: dir) }
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 6, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.bitmapData?.initialize(repeating: 255, count: bitmap.bytesPerRow * bitmap.pixelsHigh)

        for (filename, animated, shiny) in [
            ("25-s.png", false, false), ("25-shs.png", false, true),
            ("25-a.gif", true, false), ("25-sha.gif", true, true),
        ] {
            let file = dir.appendingPathComponent(filename)
            try XCTUnwrap(bitmap.representation(using: animated ? .gif : .png, properties: [:])).write(to: file)
            let firstLoad = Task { await SpriteLoader.image(speciesID: 25, animated: animated, shiny: shiny, store: store) }
            let secondLoad = Task { await SpriteLoader.image(speciesID: 25, animated: animated, shiny: shiny, store: store) }
            let result = await firstLoad.value
            let first = try XCTUnwrap(result)
            let second = await secondLoad.value
            XCTAssertTrue(second === first, "concurrent loads must converge on one image object")
            try FileManager.default.removeItem(at: file)
            XCTAssertTrue(SpriteLoader.cachedImage(
                speciesID: 25, animated: animated, shiny: shiny, directory: dir) === first)
            let again = await SpriteLoader.image(speciesID: 25, animated: animated, shiny: shiny, store: store)
            XCTAssertTrue(again === first, "the async path must also reuse the image, not just the byte cache")
        }
    }

    func testItemLoadsShareTheImageCacheInBothDirections() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("item-cache-\(UUID().uuidString)")
        let store = SpriteStore(directory: dir)
        defer { try? FileManager.default.removeItem(at: dir) }
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.bitmapData?.initialize(repeating: 255, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))

        for asyncFirst in [false, true] {
            let name = asyncFirst ? "rare-candy" : "shiny-charm"
            let file = dir.appendingPathComponent("item-\(name).png")
            XCTAssertNil(SpriteLoader.cachedItemImage(name: name, directory: dir))
            try png.write(to: file)
            let result: NSImage?
            if asyncFirst {
                let firstLoad = Task { await SpriteLoader.itemImage(name: name, store: store) }
                let secondLoad = Task { await SpriteLoader.itemImage(name: name, store: store) }
                result = await firstLoad.value
                let second = await secondLoad.value
                XCTAssertTrue(second === result, "concurrent item loads must also share their image object")
            } else {
                result = SpriteLoader.cachedItemImage(name: name, directory: dir)
            }
            let first = try XCTUnwrap(result)
            // Keep fault injection offline too: a broken image cache may still read the byte cache.
            _ = await store.data(itemName: name)
            try FileManager.default.removeItem(at: file)
            XCTAssertTrue(SpriteLoader.cachedItemImage(name: name, directory: dir) === first)
            let again = await SpriteLoader.itemImage(name: name, store: store)
            XCTAssertTrue(again === first)
        }
    }

    func testAsyncFallbacksStillReachNormalStaticImages() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sprite-fallback-\(UUID().uuidString)")
        let store = SpriteStore(directory: dir)
        defer { try? FileManager.default.removeItem(at: dir) }
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 6, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.bitmapData?.initialize(repeating: 255, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: dir.appendingPathComponent("25-s.png"))
        for filename in ["25-sha.gif", "25-shs.png", "25-a.gif", "item-rare-candy.png"] {
            // Existing corrupt cache files exercise decode failures without making network requests.
            try Data("invalid image".utf8).write(to: dir.appendingPathComponent(filename))
        }
        let result = await SpriteLoader.image(speciesID: 25, animated: true, shiny: true, store: store)
        let normal = try XCTUnwrap(result)
        XCTAssertTrue(SpriteLoader.cachedImage(speciesID: 25, directory: dir) === normal)
        XCTAssertNil(SpriteLoader.imageCache.object(forKey: dir.appendingPathComponent("25-shs.png").path as NSString),
                     "the normal fallback must not poison the shiny cache")
        let item = await SpriteLoader.itemImage(name: "rare-candy", store: store)
        XCTAssertNil(item)

        // A species outside Gen V has no GIF; that nil path must still try its PNG.
        try png.write(to: dir.appendingPathComponent("1000-s.png"))
        let staticOnly = await SpriteLoader.image(speciesID: 1000, animated: true, store: store)
        XCTAssertNotNil(staticOnly)
        XCTAssertTrue(SpriteLoader.cachedImage(speciesID: 1000, directory: dir) === staticOnly)
    }
}
