import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import PokeTokenBar

@MainActor
final class SpriteAnimationPreviewTests: XCTestCase {
    private func pixels(_ color: NSColor, canvas: Int, inset: Int = 0) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: canvas, height: canvas,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(try XCTUnwrap(color.usingColorSpace(.deviceRGB)).cgColor)
        context.fill(CGRect(x: inset, y: inset, width: canvas - inset * 2, height: canvas - inset * 2))
        return try XCTUnwrap(context.makeImage())
    }
    private func fixture() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("animation-preview-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let png = NSBitmapImageRep(cgImage: try pixels(.blue, canvas: 96, inset: 24))
        try XCTUnwrap(png.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent("25-s.png"))
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, 2, nil))
        for color in [NSColor.red, .green] {
            CGImageDestinationAddImage(destination, try pixels(color, canvas: 48),
                [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        try (data as Data).write(to: directory.appendingPathComponent("25-a.gif"))
        return directory
    }

    func testDetailFirstRenderUsesCachedAnimationCanvasAndPixels() async throws {
        let directory = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SpriteStore(directory: directory)
        let view = SpriteView(speciesID: 25, size: 82, animated: true, spriteStore: store)
        let rendered = try XCTUnwrap(ImageRenderer(content: view).cgImage)
        let bitmap = NSBitmapImageRep(cgImage: rendered)
        let center = try XCTUnwrap(bitmap.colorAt(x: 41, y: 41)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(center.redComponent, 0.9, "first render must use GIF red pixels, not static blue PNG")
        XCTAssertGreaterThan(bitmap.colorAt(x: 2, y: 41)?.alphaComponent ?? 0, 0.9,
                             "GIF must already fill its final canvas on the first render")
        let ready = SpriteLoader.cachedFrames(speciesID: 25, shiny: false, directory: directory)
        XCTAssertEqual(ready.count, 2)
        try FileManager.default.removeItem(at: directory.appendingPathComponent("25-a.gif"))
        let repeated = await SpriteLoader.animationFrames(speciesID: 25, shiny: false, store: store)
        XCTAssertTrue(ready[0].image === repeated[0].image, "repeat detail visits reuse decoded frames without disk/network")
        XCTAssertEqual(repeated.map(\.delay), [0.1, 0.1])
        let next = NSBitmapImageRep(cgImage: try XCTUnwrap(repeated[1].image.cgImage(forProposedRect: nil, context: nil, hints: nil)))
        XCTAssertGreaterThan(next.colorAt(x: 20, y: 20)?.greenComponent ?? 0, 0.9)
        // Native SwiftUI render evidence, isolated outside the repository.
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(
            to: URL(fileURLWithPath: "/private/tmp/dex-animation-first-render.png"))
    }

    func testAnimatedPlaceholderRemovesPaddingWithoutChangingStaticThumbnail() throws {
        let directory = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = try XCTUnwrap(SpriteLoader.cachedImage(speciesID: 25, directory: directory))
        let placeholder = SpriteLoader.animationPlaceholder(original)
        XCTAssertEqual(original.size, NSSize(width: 96, height: 96))
        XCTAssertEqual(placeholder.size, NSSize(width: 48, height: 48))
        XCTAssertTrue(placeholder === SpriteLoader.animationPlaceholder(original))
        XCTAssertNotEqual(SpriteView.frameTaskID(speciesID: 25, shiny: false, floor: 0, animated: false),
                          SpriteView.frameTaskID(speciesID: 25, shiny: false, floor: 0, animated: true))
        XCTAssertTrue(SpriteLoader.cachedFrames(speciesID: 25, shiny: true, directory: directory).isEmpty,
                      "a normal cached GIF must not prevent fetching a newly requested shiny GIF")
    }
}
