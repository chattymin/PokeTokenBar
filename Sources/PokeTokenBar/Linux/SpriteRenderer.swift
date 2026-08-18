#if os(Linux)
import CGtk
import Foundation

/// Turns downloaded sprite bytes into something GTK can show — a pixbuf for a window, or a PNG
/// file for the tray (which takes icon *names* on disk, not images).
///
/// Two things have to happen that writing the PNG straight to disk does not do:
///
/// 1. **Crop the transparent padding.** PokéAPI draws on a 96×96 canvas and the egg fills 28×30 of
///    it. The panel scales the whole canvas into its icon box, so an uncropped egg renders at about
///    a third of the space and looks broken rather than small. `SpriteCrop` decides the rectangle;
///    macOS applies the same one.
/// 2. **Scale up with nearest-neighbour.** These are pixel-art sprites of about 30×30 after
///    cropping. Letting the panel scale them up applies a smoothing filter and turns crisp pixels
///    into mush, so they are pre-scaled here with `GDK_INTERP_NEAREST`.
enum SpriteRenderer {
    /// Rendered size. Larger than any panel asks for, so the panel only ever scales *down* — which
    /// is the direction that stays sharp.
    fileprivate static let renderedSize = 128

    /// A cropped, nearest-scaled pixbuf at `size`. Caller owns the reference and must unref it.
    /// Returns nil if the bytes are not a readable image.
    static func render(_ data: Data, size: Int, crop: Bool = true) -> OpaquePointer? {
        guard let source = pixbuf(from: data) else { return nil }
        defer { g_object_unref(UnsafeMutableRawPointer(source)) }

        let width = Int(gdk_pixbuf_get_width(source))
        let height = Int(gdk_pixbuf_get_height(source))

        var subject = source
        var ownsSubject = false
        if crop, let rect = contentRect(of: source, width: width, height: height),
           let cropped = gdk_pixbuf_new_subpixbuf(
            source, Int32(rect.x), Int32(rect.y), Int32(rect.side), Int32(rect.side)) {
            subject = cropped
            ownsSubject = true
        }
        defer { if ownsSubject { g_object_unref(UnsafeMutableRawPointer(subject)) } }

        return gdk_pixbuf_scale_simple(subject, Int32(size), Int32(size), GDK_INTERP_NEAREST)
    }

    /// Write `data` to `file`, cropped and scaled — the tray takes a path, not an image.
    /// Returns false if the bytes are not a readable image, in which case the caller keeps whatever
    /// icon is already showing.
    static func write(_ data: Data, to file: URL) -> Bool {
        guard let scaled = render(data, size: renderedSize) else { return false }
        defer { g_object_unref(UnsafeMutableRawPointer(scaled)) }
        // `gdk_pixbuf_save` is variadic and unreachable from Swift; `savev` is the same call with
        // the options passed as arrays instead.
        return gdk_pixbuf_savev(scaled, file.path, "png", nil, nil, nil) != 0
    }

    /// Decode image bytes without touching the filesystem first.
    private static func pixbuf(from data: Data) -> OpaquePointer? {
        guard let loader = gdk_pixbuf_loader_new() else { return nil }
        let ok = data.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            return gdk_pixbuf_loader_write(
                loader, base.assumingMemoryBound(to: guchar.self), gsize(data.count), nil) != 0
        }
        // Close before reading: the pixbuf is only complete once the loader is told the stream ended.
        let closed = gdk_pixbuf_loader_close(loader, nil) != 0
        guard ok, closed, let pixbuf = gdk_pixbuf_loader_get_pixbuf(loader) else {
            g_object_unref(UnsafeMutableRawPointer(loader))
            return nil
        }
        // `get_pixbuf` returns a borrowed reference owned by the loader, so take one of our own
        // before releasing it.
        g_object_ref(UnsafeMutableRawPointer(pixbuf))
        g_object_unref(UnsafeMutableRawPointer(loader))
        return pixbuf
    }

    fileprivate static func contentRect(
        of pixbuf: OpaquePointer, width: Int, height: Int
    ) -> SpriteCrop.Rect? {
        // Without an alpha channel every pixel is content, and the crop is the whole canvas.
        guard gdk_pixbuf_get_has_alpha(pixbuf) != 0,
              let pixels = gdk_pixbuf_get_pixels(pixbuf) else {
            return SpriteCrop.squareContentRect(width: width, height: height) { _, _ in true }
        }
        let stride = Int(gdk_pixbuf_get_rowstride(pixbuf))
        let channels = Int(gdk_pixbuf_get_n_channels(pixbuf))
        let threshold = UInt8(SpriteCrop.opaqueAlphaThreshold * 255)
        let alphaOffset: Int = channels - 1
        return SpriteCrop.squareContentRect(width: width, height: height) { x, y in
            let row: Int = y * stride
            let column: Int = x * channels
            let alpha: UInt8 = pixels[row + column + alphaOffset]
            return alpha > threshold
        }
    }
}

extension SpriteRenderer {
    /// One decoded frame of an animated sprite, already written to disk.
    struct Frame {
        /// Icon name (filename without extension) — what AppIndicator wants.
        let name: String
        /// How long to hold it, native delay before any floor is applied.
        let delay: TimeInterval
    }

    /// Explode an animated GIF into numbered PNGs next to the static icons.
    ///
    /// The tray takes icon *names*, not images, so every frame has to exist as a file before it can
    /// be shown. They are written once per species and then only cycled, which keeps the animation
    /// loop free of disk work.
    ///
    /// Returns an empty array for a single-frame image, so callers fall back to the static icon
    /// rather than "animating" one frame forever.
    static func writeFrames(_ data: Data, directory: URL, prefix: String) -> [Frame] {
        guard let loader = gdk_pixbuf_loader_new() else { return [] }
        let wrote = data.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            return gdk_pixbuf_loader_write(
                loader, base.assumingMemoryBound(to: guchar.self), gsize(data.count), nil) != 0
        }
        let closed = gdk_pixbuf_loader_close(loader, nil) != 0
        guard wrote, closed, let animation = gdk_pixbuf_loader_get_animation(loader) else {
            g_object_unref(UnsafeMutableRawPointer(loader))
            return []
        }
        g_object_ref(UnsafeMutableRawPointer(animation))
        g_object_unref(UnsafeMutableRawPointer(loader))
        defer { g_object_unref(UnsafeMutableRawPointer(animation)) }

        guard gdk_pixbuf_animation_is_static_image(animation) == 0 else { return [] }

        // The iterator is driven by a clock we advance ourselves rather than by wall time, so the
        // whole loop is extracted immediately instead of in real time.
        var clock = GTimeVal(tv_sec: 0, tv_usec: 0)
        guard let iterator = gdk_pixbuf_animation_get_iter(animation, &clock) else { return [] }
        defer { g_object_unref(UnsafeMutableRawPointer(iterator)) }

        var frames: [Frame] = []
        var firstSignature: Int?
        var lastSignature: Int?
        // The cap is a backstop for a malformed animation; normal exit is loop detection below.
        let maximumFrames = 120
        while frames.count < maximumFrames {
            let milliseconds = gdk_pixbuf_animation_iter_get_delay_time(iterator)
            guard milliseconds >= 0 else { break }   // -1: not animated after all
            guard let pixbuf = gdk_pixbuf_animation_iter_get_pixbuf(iterator) else { break }
            let fingerprint = signature(of: pixbuf)

            // The iterator hands back frame 0 twice before it starts moving, and some sprites
            // repeat a frame mid-loop. Merge a repeat into the previous frame's delay instead of
            // writing the same image again — and crucially, do not mistake it for the loop point.
            if fingerprint == lastSignature {
                if !frames.isEmpty {
                    let previous = frames.removeLast()
                    frames.append(Frame(name: previous.name,
                                        delay: previous.delay + TimeInterval(milliseconds) / 1000))
                }
                advance(iterator, &clock, milliseconds)
                continue
            }
            // Back to the first frame after at least two distinct ones: a full loop is captured.
            if let firstSignature, fingerprint == firstSignature, frames.count >= 2 { break }
            if firstSignature == nil { firstSignature = fingerprint }
            lastSignature = fingerprint

            let name = "\(prefix)-f\(frames.count)"
            let file = directory.appendingPathComponent("\(name).png")
            guard writeCroppedScaled(pixbuf, to: file) else { break }
            frames.append(Frame(name: name, delay: TimeInterval(milliseconds) / 1000))

            advance(iterator, &clock, milliseconds)
        }
        return frames.count > 1 ? frames : []
    }

    /// Crop, scale and save one already-decoded pixbuf.
    private static func writeCroppedScaled(_ source: OpaquePointer, to file: URL) -> Bool {
        let width = Int(gdk_pixbuf_get_width(source))
        let height = Int(gdk_pixbuf_get_height(source))
        var subject = source
        var ownsSubject = false
        if let rect = contentRect(of: source, width: width, height: height),
           let cropped = gdk_pixbuf_new_subpixbuf(
            source, Int32(rect.x), Int32(rect.y), Int32(rect.side), Int32(rect.side)) {
            subject = cropped
            ownsSubject = true
        }
        defer { if ownsSubject { g_object_unref(UnsafeMutableRawPointer(subject)) } }
        guard let scaled = gdk_pixbuf_scale_simple(
            subject, Int32(renderedSize), Int32(renderedSize), GDK_INTERP_NEAREST) else { return false }
        defer { g_object_unref(UnsafeMutableRawPointer(scaled)) }
        return gdk_pixbuf_savev(scaled, file.path, "png", nil, nil, nil) != 0
    }
}


extension SpriteRenderer {
    /// An animated sprite decoded into in-memory frames, cropped and scaled like the static path.
    ///
    /// Separate from `writeFrames` because the window can hold pixbufs directly — only the tray is
    /// forced through files, and doing disk I/O for an on-screen animation would be silly.
    /// **The caller owns every pixbuf and must unref them.**
    static func renderFrames(_ data: Data, size: Int) -> [(pixbuf: OpaquePointer, delay: TimeInterval)] {
        guard let loader = gdk_pixbuf_loader_new() else { return [] }
        let wrote = data.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            return gdk_pixbuf_loader_write(
                loader, base.assumingMemoryBound(to: guchar.self), gsize(data.count), nil) != 0
        }
        let closed = gdk_pixbuf_loader_close(loader, nil) != 0
        guard wrote, closed, let animation = gdk_pixbuf_loader_get_animation(loader) else {
            g_object_unref(UnsafeMutableRawPointer(loader))
            return []
        }
        g_object_ref(UnsafeMutableRawPointer(animation))
        g_object_unref(UnsafeMutableRawPointer(loader))
        defer { g_object_unref(UnsafeMutableRawPointer(animation)) }
        guard gdk_pixbuf_animation_is_static_image(animation) == 0 else { return [] }

        var clock = GTimeVal(tv_sec: 0, tv_usec: 0)
        guard let iterator = gdk_pixbuf_animation_get_iter(animation, &clock) else { return [] }
        defer { g_object_unref(UnsafeMutableRawPointer(iterator)) }

        var frames: [(OpaquePointer, TimeInterval)] = []
        var firstSignature: Int?
        var lastSignature: Int?
        let maximumFrames = 120   // same runaway guard as writeFrames
        while frames.count < maximumFrames {
            let milliseconds = gdk_pixbuf_animation_iter_get_delay_time(iterator)
            guard milliseconds >= 0, let source = gdk_pixbuf_animation_iter_get_pixbuf(iterator)
            else { break }
            let fingerprint = signature(of: source)
            if fingerprint == lastSignature {   // repeat: extend the previous frame (see writeFrames)
                if let last = frames.popLast() {
                    frames.append((last.0, last.1 + TimeInterval(milliseconds) / 1000))
                }
                advance(iterator, &clock, milliseconds)
                continue
            }
            if let firstSignature, fingerprint == firstSignature, frames.count >= 2 { break }
            if firstSignature == nil { firstSignature = fingerprint }
            lastSignature = fingerprint
            if let scaled = croppedScaled(source, size: size) {
                frames.append((scaled, TimeInterval(milliseconds) / 1000))
            }
            advance(iterator, &clock, milliseconds)
        }
        if frames.count > 1 { return frames }
        for frame in frames { g_object_unref(UnsafeMutableRawPointer(frame.0)) }
        return []
    }

    /// Crop to content and scale, returning a new pixbuf the caller owns.
    fileprivate static func croppedScaled(_ source: OpaquePointer, size: Int) -> OpaquePointer? {
        let width = Int(gdk_pixbuf_get_width(source))
        let height = Int(gdk_pixbuf_get_height(source))
        var subject = source
        var ownsSubject = false
        if let rect = contentRect(of: source, width: width, height: height),
           let cropped = gdk_pixbuf_new_subpixbuf(
            source, Int32(rect.x), Int32(rect.y), Int32(rect.side), Int32(rect.side)) {
            subject = cropped
            ownsSubject = true
        }
        defer { if ownsSubject { g_object_unref(UnsafeMutableRawPointer(subject)) } }
        return gdk_pixbuf_scale_simple(subject, Int32(size), Int32(size), GDK_INTERP_NEAREST)
    }
}


extension SpriteRenderer {
    /// Step the iterator's synthetic clock forward by one frame's delay.
    fileprivate static func advance(
        _ iterator: OpaquePointer, _ clock: inout GTimeVal, _ milliseconds: Int32
    ) {
        clock.tv_usec += glong(milliseconds) * 1000
        clock.tv_sec += glong(clock.tv_usec / 1_000_000)
        clock.tv_usec %= 1_000_000
        _ = gdk_pixbuf_animation_iter_advance(iterator, &clock)
    }

    /// A cheap fingerprint of a pixbuf's pixels, used to spot when a GIF has looped.
    ///
    /// A GIF has no end — the iterator happily cycles forever — so extraction needs its own stop
    /// condition. Without one, a 20-frame sprite is written out to whatever cap the loop imposes,
    /// duplicating frames on disk and in memory for no gain. When a later frame is byte-identical
    /// to the first, one full loop has been captured and the rest is repetition.
    fileprivate static func signature(of pixbuf: OpaquePointer) -> Int {
        guard let pixels = gdk_pixbuf_get_pixels(pixbuf) else { return 0 }
        let height = Int(gdk_pixbuf_get_height(pixbuf))
        let stride = Int(gdk_pixbuf_get_rowstride(pixbuf))
        let count = height * stride
        var hash = 5381
        // Sampling rather than hashing every byte: frames differ in whole regions, and a stride of
        // 7 still separates them while keeping extraction off the critical path.
        var index = 0
        while index < count {
            hash = (hash &* 33) &+ Int(pixels[index])
            index += 7
        }
        return hash
    }
}

#endif   // os(Linux)
