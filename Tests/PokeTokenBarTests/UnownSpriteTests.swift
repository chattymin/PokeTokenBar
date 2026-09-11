import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import PokeTokenBar

final class UnownSpriteTests: XCTestCase {
    func testExistingUnownAndExplicitAKeepLegacyCacheKeys() {
        for (animated, shiny, expected) in [
            (false, false, "201-s"), (true, false, "201-a"),
            (false, true, "201-shs"), (true, true, "201-sha"),
        ] {
            XCTAssertEqual(SpriteStore.cacheKey(speciesID: 201, animated: animated, shiny: shiny), expected)
            XCTAssertEqual(SpriteStore.cacheKey(speciesID: 201, animated: animated, shiny: shiny,
                                                 unownForm: .a), expected)
        }
    }

    /// 종 ID가 같아도 다른 글자·색·형식의 이미지를 캐시에서 꺼내면 안 된다.
    func testAll28FormsHaveIndependentNormalShinyAndAnimatedCaches() {
        var keys: Set<String> = []
        for form in UnownForm.allCases {
            for animated in [false, true] {
                for shiny in [false, true] {
                    let key = SpriteStore.cacheKey(speciesID: 201, animated: animated,
                                                   shiny: shiny, unownForm: form)
                    XCTAssertTrue(keys.insert(key).inserted, "Cache collision for \(form), \(animated), \(shiny)")
                }
            }
        }
        XCTAssertEqual(keys.count, 28 * 4)
    }

    /// PokeAPI에서 확인한 파일명. A는 접미사가 없고, 문장부호는 영문 이름을 쓴다.
    func testFormURLsMatchPokeAPIAssetsInAllFourDirectories() {
        let base = "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon"
        let examples: [(UnownForm?, String)] = [
            (nil, "201"), (.a, "201"), (.b, "201-b"), (.z, "201-z"),
            (.exclamation, "201-exclamation"), (.question, "201-question"),
        ]
        for (form, asset) in examples {
            XCTAssertEqual(SpriteStore.spriteURL(speciesID: 201, animated: false, shiny: false,
                                                  unownForm: form).absoluteString,
                           "\(base)/\(asset).png")
            XCTAssertEqual(SpriteStore.spriteURL(speciesID: 201, animated: false, shiny: true,
                                                  unownForm: form).absoluteString,
                           "\(base)/shiny/\(asset).png")
            XCTAssertEqual(SpriteStore.spriteURL(speciesID: 201, animated: true, shiny: false,
                                                  unownForm: form).absoluteString,
                           "\(base)/versions/generation-v/black-white/animated/\(asset).gif")
            XCTAssertEqual(SpriteStore.spriteURL(speciesID: 201, animated: true, shiny: true,
                                                  unownForm: form).absoluteString,
                           "\(base)/versions/generation-v/black-white/animated/shiny/\(asset).gif")
        }
    }

    func testOtherSpeciesIgnoreAnUnownForm() {
        for animated in [false, true] {
            for shiny in [false, true] {
                XCTAssertEqual(SpriteStore.cacheKey(speciesID: 25, animated: animated, shiny: shiny,
                                                     unownForm: .question),
                               SpriteStore.cacheKey(speciesID: 25, animated: animated, shiny: shiny))
                XCTAssertEqual(SpriteStore.spriteURL(speciesID: 25, animated: animated, shiny: shiny,
                                                      unownForm: .question),
                               SpriteStore.spriteURL(speciesID: 25, animated: animated, shiny: shiny))
            }
        }
    }
}

/// Exercise the current byte, image and decoded-animation caches using generated pixels only.
/// A correct filename helper alone cannot prove the production loaders forward the selected form.
@MainActor
final class UnownSpriteCacheTests: XCTestCase {
    private let forms: [(UnownForm, String)] = [
        (.a, "201"), (.b, "201-b"), (.exclamation, "201-exclamation"), (.question, "201-question"),
    ]

    private func directory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("unown-sprites-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func pixels(width: Int, height: Int) throws -> NSBitmapImageRep {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.bitmapData?.initialize(repeating: 255, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        return bitmap
    }

    private func animatedPixels(width: Int, height: Int) throws -> Data {
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            data, UTType.gif.identifier as CFString, 2, nil))
        let image = try XCTUnwrap(pixels(width: width, height: height).cgImage)
        for delay in [0.1, 0.2] {
            CGImageDestinationAddImage(destination, image,
                [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    func testByteAndImageCachesKeepLettersSeparateAcrossAllFormats() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SpriteStore(directory: directory)
        var images: [NSImage] = []

        for (index, entry) in forms.enumerated() {
            let (form, stem) = entry
            for animated in [false, true] {
                for shiny in [false, true] {
                    let expectedSize = NSSize(width: 4 + index, height: shiny ? 9 : 6)
                    let bitmap = try pixels(width: Int(expectedSize.width), height: Int(expectedSize.height))
                    let bytes = try XCTUnwrap(bitmap.representation(using: animated ? .gif : .png, properties: [:]))
                    let file = directory.appendingPathComponent(
                        "\(stem)-\(shiny ? "sh" : "")\(animated ? "a.gif" : "s.png")")
                    try bytes.write(to: file)
                    let loadedBytes = await store.data(speciesID: 201, animated: animated,
                                                        shiny: shiny, unownForm: form)
                    XCTAssertEqual(loadedBytes, bytes, "The byte cache must include the selected letter")
                    let loaded = await SpriteLoader.image(speciesID: 201, animated: animated,
                                                           shiny: shiny, store: store, unownForm: form)
                    let image = try XCTUnwrap(loaded)
                    XCTAssertEqual(image.size, expectedSize)
                    XCTAssertFalse(images.contains { $0 === image }, "Different variants must not share decoded images")
                    images.append(image)
                    try FileManager.default.removeItem(at: file)
                    XCTAssertTrue(SpriteLoader.cachedImage(speciesID: 201, animated: animated, shiny: shiny,
                                                             directory: directory, unownForm: form) === image)
                    let repeatedBytes = await store.data(speciesID: 201, animated: animated,
                                                          shiny: shiny, unownForm: form)
                    XCTAssertEqual(repeatedBytes, bytes, "The warm byte lookup must survive removal of its file")
                    let repeated = await SpriteLoader.image(speciesID: 201, animated: animated,
                                                             shiny: shiny, store: store, unownForm: form)
                    XCTAssertTrue(repeated === image)
                }
            }
        }
    }

    func testShinyStaticFallbackKeepsLetterAndDoesNotHideALaterShiny() throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let png = try XCTUnwrap(pixels(width: 4, height: 6).representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent("201-s.png"))
        let a = try XCTUnwrap(SpriteLoader.cachedImage(speciesID: 201, directory: directory))
        XCTAssertNil(SpriteLoader.cachedImage(speciesID: 201, shiny: true, directory: directory, unownForm: .b),
                     "Missing B must not fall back to A")
        try png.write(to: directory.appendingPathComponent("201-b-s.png"))
        let b = try XCTUnwrap(SpriteLoader.cachedImage(speciesID: 201, directory: directory, unownForm: .b))
        XCTAssertFalse(a === b)
        XCTAssertTrue(SpriteLoader.cachedImage(speciesID: 201, shiny: true,
                                               directory: directory, unownForm: .b) === b)
        try png.write(to: directory.appendingPathComponent("201-b-shs.png"))
        let shinyB = try XCTUnwrap(SpriteLoader.cachedImage(speciesID: 201, shiny: true,
                                                             directory: directory, unownForm: .b))
        XCTAssertFalse(shinyB === b, "Normal B fallback must not poison the shiny B key")
        XCTAssertTrue(SpriteLoader.cachedImage(speciesID: 201, directory: directory, unownForm: .a) === a)
    }

    func testAsyncAnimationAndShinyImageFallbacksKeepSelectedLetter() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SpriteStore(directory: directory)
        let png = try XCTUnwrap(pixels(width: 4, height: 7).representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent("201-b-s.png"))
        // Invalid local files exercise all fallback branches without making network requests.
        for name in ["201-b-sha.gif", "201-b-shs.png", "201-b-a.gif"] {
            try Data("invalid image".utf8).write(to: directory.appendingPathComponent(name))
        }
        let other = try XCTUnwrap(pixels(width: 12, height: 12).representation(using: .png, properties: [:]))
        for name in ["201-s.png", "201-shs.png", "201-a.gif", "201-sha.gif"] {
            try other.write(to: directory.appendingPathComponent(name))
        }
        let result = await SpriteLoader.image(speciesID: 201, animated: true, shiny: true,
                                               store: store, unownForm: .b)
        let b = try XCTUnwrap(result)
        XCTAssertEqual(b.size, NSSize(width: 4, height: 7))
        XCTAssertTrue(SpriteLoader.cachedImage(speciesID: 201, directory: directory, unownForm: .b) === b)
        XCTAssertNil(SpriteLoader.imageCache.object(
            forKey: directory.appendingPathComponent("201-b-shs.png").path as NSString))
    }

    func testDecodedAnimationCacheKeepsLettersColorsAndCanvasSeparate() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SpriteStore(directory: directory)
        var firstImages: [NSImage] = []
        for (index, entry) in forms.enumerated() {
            let (form, stem) = entry
            for shiny in [false, true] {
                let size = NSSize(width: 4 + index, height: shiny ? 10 : 6)
                let file = directory.appendingPathComponent("\(stem)-\(shiny ? "sh" : "")a.gif")
                try animatedPixels(width: Int(size.width), height: Int(size.height)).write(to: file)
                let frames = SpriteLoader.cachedFrames(speciesID: 201, shiny: shiny,
                                                         directory: directory, unownForm: form)
                XCTAssertEqual(frames.count, 2)
                let first = try XCTUnwrap(frames.first?.image)
                XCTAssertEqual(first.size, size)
                XCTAssertFalse(firstImages.contains { $0 === first }, "Decoded GIFs must include form and shiny identity")
                firstImages.append(first)
                try FileManager.default.removeItem(at: file)
                let repeated = await SpriteLoader.animationFrames(speciesID: 201, shiny: shiny,
                                                                    store: store, unownForm: form)
                XCTAssertTrue(repeated.first?.image === first)
                XCTAssertEqual(repeated.map(\.delay), [0.1, 0.2])
            }
        }
    }

    func testDecodedShinyFallbackUsesTheSameLetter() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SpriteStore(directory: directory)
        try animatedPixels(width: 4, height: 7).write(to: directory.appendingPathComponent("201-b-a.gif"))
        try animatedPixels(width: 12, height: 12).write(to: directory.appendingPathComponent("201-a.gif"))
        try animatedPixels(width: 12, height: 12).write(to: directory.appendingPathComponent("201-sha.gif"))
        try Data("invalid image".utf8).write(to: directory.appendingPathComponent("201-b-sha.gif"))
        let result = await SpriteLoader.animationFrames(speciesID: 201, shiny: true,
                                                         store: store, unownForm: .b)
        let first = try XCTUnwrap(result.first?.image)
        XCTAssertEqual(first.size, NSSize(width: 4, height: 7))
        let normal = SpriteLoader.cachedFrames(speciesID: 201, shiny: false,
                                                directory: directory, unownForm: .b)
        XCTAssertTrue(first === normal.first?.image)
        XCTAssertTrue(SpriteLoader.cachedFrames(speciesID: 201, shiny: true,
                                                 directory: directory, unownForm: .b).isEmpty)
    }
}
