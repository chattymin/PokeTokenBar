import Foundation

/// Where the visible content of a sprite sits inside its canvas.
///
/// PokéAPI sprites are drawn on a fixed 96×96 canvas and the subject rarely fills it — the egg
/// occupies 28×30, about 29% of the area. Anything that scales the whole canvas into a small fixed
/// box (the macOS menu bar, the Linux tray icon) therefore renders a subject a third of the size it
/// could be. Cropping to content is what fixes that.
///
/// The geometry lives here, apart from any image API, because both frontends need the same answer
/// and it is the part worth testing: the pixel access differs (NSBitmapImageRep vs GdkPixbuf) but
/// the rectangle must not.
enum SpriteCrop {
    struct Rect: Equatable {
        let x: Int, y: Int, side: Int
    }

    /// The opaque bounding box, grown into a centred square and clamped to the canvas.
    ///
    /// Square, not the raw bounding box: the egg's content is 28×30 (taller than wide), and
    /// cropping to that would stretch it sideways in a square frame. Squaring first preserves the
    /// aspect ratio.
    ///
    /// Returns nil for a fully transparent canvas — the caller keeps the original rather than
    /// cropping to nothing.
    static func squareContentRect(
        width: Int, height: Int, isOpaque: (Int, Int) -> Bool
    ) -> Rect? {
        guard width > 0, height > 0 else { return nil }
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where isOpaque(x, y) {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }

        let boxWidth = maxX - minX + 1
        let boxHeight = maxY - minY + 1
        let side = min(max(boxWidth, boxHeight), min(width, height))
        let x = max(0, min(minX - (side - boxWidth) / 2, width - side))
        let y = max(0, min(minY - (side - boxHeight) / 2, height - side))
        return Rect(x: x, y: y, side: side)
    }

    /// Alpha above which a pixel counts as content. Matches the macOS implementation this was
    /// extracted from — sprites are hard-edged, so anything above "numerically nonzero" is subject.
    static let opaqueAlphaThreshold = 0.01
}
