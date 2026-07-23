#if os(Windows)
import Foundation
import WinSDK

/// PNG bytes → Win32 `HICON`, using WIC (Windows Imaging Component, COM) to decode and GDI to
/// build the icon. Shared by the tray icon (Task-3 #1) and, later, the popover sprite views.
enum WindowsImaging {
    /// Decode a PNG and build an HICON. The PokéAPI sprites carry a lot of transparent padding, so
    /// the content is trimmed and re-centered into a square (fills more of the fixed-size tray slot →
    /// the sprite reads bigger). Caller owns the HICON (DestroyIcon).
    static func hicon(fromPNG data: Data) -> HICON? {
        guard let img = decodePNG(data) else { return nil }
        let t = trimmedSquare(img)
        return makeHICON(width: t.width, height: t.height, bgra: t.bgra)
    }

    struct DecodedImage { let width: Int; let height: Int; let bgra: [UInt8] }

    /// Alpha bounding box (pixels with alpha > threshold); nil if fully transparent.
    private static func alphaBBox(_ bgra: [UInt8], _ w: Int, _ h: Int, threshold: UInt8 = 8)
        -> (minX: Int, minY: Int, maxX: Int, maxY: Int)? {
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            let row = y * w
            for x in 0..<w where bgra[(row + x) * 4 + 3] > threshold {
                if x < minX { minX = x }; if x > maxX { maxX = x }
                if y < minY { minY = y }; if y > maxY { maxY = y }
            }
        }
        return maxX >= minX ? (minX, minY, maxX, maxY) : nil
    }

    /// Crop `bgra` (w×h) to `box` and center it into a square canvas sized to the longer side plus a
    /// small margin — content fills the icon without distortion (square → no stretch in the tray slot).
    private static func squareCrop(_ bgra: [UInt8], _ w: Int, _ h: Int,
                                   _ box: (minX: Int, minY: Int, maxX: Int, maxY: Int),
                                   marginFrac: Double = 0.10) -> DecodedImage {
        let bw = box.maxX - box.minX + 1, bh = box.maxY - box.minY + 1
        let side = max(bw, bh) + Int((Double(max(bw, bh)) * marginFrac).rounded()) * 2
        var out = [UInt8](repeating: 0, count: side * side * 4)
        let offX = (side - bw) / 2, offY = (side - bh) / 2
        for y in 0..<bh {
            for x in 0..<bw {
                let s = ((box.minY + y) * w + (box.minX + x)) * 4
                let d = ((offY + y) * side + (offX + x)) * 4
                out[d] = bgra[s]; out[d + 1] = bgra[s + 1]; out[d + 2] = bgra[s + 2]; out[d + 3] = bgra[s + 3]
            }
        }
        return DecodedImage(width: side, height: side, bgra: out)
    }

    /// Trim transparent margins and re-center into a square so the content fills the icon.
    static func trimmedSquare(_ img: DecodedImage) -> DecodedImage {
        guard let box = alphaBBox(img.bgra, img.width, img.height) else { return img }
        return squareCrop(img.bgra, img.width, img.height, box)
    }

    /// Decode an animated GIF into per-frame HICONs (composited onto a persistent canvas, keeping
    /// previous pixels under transparent ones). Returns >1 icons, or nil (not animated / failure).
    /// Caller destroys the HICONs.
    static func hiconsFromGIF(_ data: Data) -> [HICON]? {
        _ = CoInitializeEx(nil, DWORD(COINIT_APARTMENTTHREADED.rawValue))
        var clsid = CLSID_WICImagingFactory
        var iid = IID_IWICImagingFactory
        var rawFactory: UnsafeMutableRawPointer?
        guard CoCreateInstance(&clsid, nil, DWORD(CLSCTX_INPROC_SERVER.rawValue), &iid, &rawFactory) >= 0,
              let fr = rawFactory else { return nil }
        let factory = fr.assumingMemoryBound(to: IWICImagingFactory.self)
        defer { _ = factory.pointee.lpVtbl.pointee.Release(factory) }

        var bytes = [UInt8](data)
        var stream: UnsafeMutablePointer<IWICStream>?
        guard factory.pointee.lpVtbl.pointee.CreateStream(factory, &stream) >= 0, let stream else { return nil }
        defer { _ = stream.pointee.lpVtbl.pointee.Release(stream) }
        guard bytes.withUnsafeMutableBufferPointer({ buf in
            stream.pointee.lpVtbl.pointee.InitializeFromMemory(stream, buf.baseAddress, DWORD(buf.count))
        }) >= 0 else { return nil }

        var decoder: UnsafeMutablePointer<IWICBitmapDecoder>?
        let sPtr = UnsafeMutableRawPointer(stream).assumingMemoryBound(to: IStream.self)
        guard factory.pointee.lpVtbl.pointee.CreateDecoderFromStream(
            factory, sPtr, nil, WICDecodeMetadataCacheOnLoad, &decoder) >= 0, let decoder else { return nil }
        defer { _ = decoder.pointee.lpVtbl.pointee.Release(decoder) }

        var count: UINT = 0
        guard decoder.pointee.lpVtbl.pointee.GetFrameCount(decoder, &count) >= 0, count > 1 else { return nil }

        // GIF frames are partial sub-images placed at (Left,Top) on a logical screen, with a disposal
        // rule per frame. Composite them properly onto a persistent canvas, honoring offset + disposal
        // (2 = restore-to-background, 3 = restore-to-previous) — otherwise moving sprites leave ghosts.
        var globalReader: UnsafeMutablePointer<IWICMetadataQueryReader>?
        _ = decoder.pointee.lpVtbl.pointee.GetMetadataQueryReader(decoder, &globalReader)
        defer { if let g = globalReader { _ = g.pointee.lpVtbl.pointee.Release(g) } }
        guard let f0 = decodeFrame(factory, decoder, 0) else { return nil }
        let lw = metaInt(globalReader, "/logscrdesc/Width") ?? f0.width
        let lh = metaInt(globalReader, "/logscrdesc/Height") ?? f0.height
        guard lw > 0, lh > 0 else { return nil }

        var canvas = [UInt8](repeating: 0, count: lw * lh * 4)
        var saved: [UInt8]?
        var composited: [[UInt8]] = []   // one full lw×lh canvas per frame (trimmed together below)
        for i in 0..<Int(count) {
            var frame: UnsafeMutablePointer<IWICBitmapFrameDecode>?
            guard decoder.pointee.lpVtbl.pointee.GetFrame(decoder, UINT(i), &frame) >= 0, let frame else { continue }
            var fReader: UnsafeMutablePointer<IWICMetadataQueryReader>?
            _ = frame.pointee.lpVtbl.pointee.GetMetadataQueryReader(frame, &fReader)
            let left = metaInt(fReader, "/imgdesc/Left") ?? 0
            let top = metaInt(fReader, "/imgdesc/Top") ?? 0
            let disposal = metaInt(fReader, "/grctlext/Disposal") ?? 0
            if let r = fReader { _ = r.pointee.lpVtbl.pointee.Release(r) }
            _ = frame.pointee.lpVtbl.pointee.Release(frame)

            guard let f = decodeFrame(factory, decoder, UINT(i)) else { continue }
            if disposal == 3 { saved = canvas }   // remember state to restore after this frame

            for y in 0..<f.height {
                let cy = top + y
                if cy < 0 || cy >= lh { continue }
                for x in 0..<f.width {
                    let s = (y * f.width + x) * 4
                    if f.bgra[s + 3] == 0 { continue }   // GIF transparent index → leave canvas
                    let cx = left + x
                    if cx < 0 || cx >= lw { continue }
                    let d = (cy * lw + cx) * 4
                    canvas[d] = f.bgra[s]; canvas[d+1] = f.bgra[s+1]; canvas[d+2] = f.bgra[s+2]; canvas[d+3] = f.bgra[s+3]
                }
            }
            composited.append(canvas)

            if disposal == 2 {   // restore-to-background: clear this frame's rect for the next frame
                for y in top..<min(top + f.height, lh) where y >= 0 {
                    for x in left..<min(left + f.width, lw) where x >= 0 {
                        let d = (y * lw + x) * 4
                        canvas[d] = 0; canvas[d+1] = 0; canvas[d+2] = 0; canvas[d+3] = 0
                    }
                }
            } else if disposal == 3, let s = saved {
                canvas = s
            }
        }
        // Trim by the UNION bbox across all frames (a per-frame bbox would jitter the animation), then
        // re-center each into the same square so the sprite fills the tray slot but stays stable.
        var union: (minX: Int, minY: Int, maxX: Int, maxY: Int)?
        for f in composited {
            guard let b = alphaBBox(f, lw, lh) else { continue }
            union = union.map { (min($0.minX, b.minX), min($0.minY, b.minY), max($0.maxX, b.maxX), max($0.maxY, b.maxY)) } ?? b
        }
        var icons: [HICON] = []
        for f in composited {
            let img: DecodedImage = union.map { squareCrop(f, lw, lh, $0) } ?? DecodedImage(width: lw, height: lh, bgra: f)
            if let ic = makeHICON(width: img.width, height: img.height, bgra: img.bgra) { icons.append(ic) }
        }
        return icons.count > 1 ? icons : nil
    }

    /// Read a small unsigned-integer GIF metadata value (UI1/UI2) by name, via a byte-offset read of
    /// the PROPVARIANT union (avoids the Swift-imported anonymous-union member naming).
    private static func metaInt(_ reader: UnsafeMutablePointer<IWICMetadataQueryReader>?, _ name: String) -> Int? {
        guard let reader else { return nil }
        var pv = PROPVARIANT()
        let nameW = Array(name.utf16) + [0]
        let hr = nameW.withUnsafeBufferPointer { reader.pointee.lpVtbl.pointee.GetMetadataByName(reader, $0.baseAddress, &pv) }
        guard hr >= 0 else { return nil }
        let (vt, v) = withUnsafeBytes(of: pv) {
            ($0.load(fromByteOffset: 0, as: UInt16.self), $0.load(fromByteOffset: 8, as: UInt16.self))
        }
        guard vt != 0 else { return nil }          // VT_EMPTY
        return vt == 17 ? Int(v & 0xFF) : Int(v)    // VT_UI1 vs VT_UI2
    }

    /// Decode one GIF frame to 32bpp BGRA at its own size.
    private static func decodeFrame(_ factory: UnsafeMutablePointer<IWICImagingFactory>,
                                    _ decoder: UnsafeMutablePointer<IWICBitmapDecoder>,
                                    _ index: UINT) -> DecodedImage? {
        var frame: UnsafeMutablePointer<IWICBitmapFrameDecode>?
        guard decoder.pointee.lpVtbl.pointee.GetFrame(decoder, index, &frame) >= 0, let frame else { return nil }
        defer { _ = frame.pointee.lpVtbl.pointee.Release(frame) }
        var converter: UnsafeMutablePointer<IWICFormatConverter>?
        guard factory.pointee.lpVtbl.pointee.CreateFormatConverter(factory, &converter) >= 0, let converter else { return nil }
        defer { _ = converter.pointee.lpVtbl.pointee.Release(converter) }
        var pf = GUID_WICPixelFormat32bppBGRA
        let src = UnsafeMutableRawPointer(frame).assumingMemoryBound(to: IWICBitmapSource.self)
        guard converter.pointee.lpVtbl.pointee.Initialize(
            converter, src, &pf, WICBitmapDitherTypeNone, nil, 0.0, WICBitmapPaletteTypeCustom) >= 0 else { return nil }
        var fw: UINT = 0, fh: UINT = 0
        guard converter.pointee.lpVtbl.pointee.GetSize(converter, &fw, &fh) >= 0, fw > 0, fh > 0 else { return nil }
        let stride = Int(fw) * 4
        var buffer = [UInt8](repeating: 0, count: stride * Int(fh))
        guard buffer.withUnsafeMutableBufferPointer({ buf in
            converter.pointee.lpVtbl.pointee.CopyPixels(converter, nil, UINT(stride), UINT(buf.count), buf.baseAddress)
        }) >= 0 else { return nil }
        return DecodedImage(width: Int(fw), height: Int(fh), bgra: buffer)
    }

    /// Decode PNG → 32bpp straight-alpha BGRA pixels via WIC.
    static func decodePNG(_ data: Data) -> DecodedImage? {
        _ = CoInitializeEx(nil, DWORD(COINIT_APARTMENTTHREADED.rawValue))

        var clsid = CLSID_WICImagingFactory
        var iid = IID_IWICImagingFactory
        var rawFactory: UnsafeMutableRawPointer?
        guard CoCreateInstance(&clsid, nil, DWORD(CLSCTX_INPROC_SERVER.rawValue), &iid, &rawFactory) >= 0,
              let factoryRaw = rawFactory else { return nil }
        let factory = factoryRaw.assumingMemoryBound(to: IWICImagingFactory.self)
        defer { _ = factory.pointee.lpVtbl.pointee.Release(factory) }

        // Stream over a stable copy of the PNG bytes (must outlive decoding).
        var bytes = [UInt8](data)
        var stream: UnsafeMutablePointer<IWICStream>?
        guard factory.pointee.lpVtbl.pointee.CreateStream(factory, &stream) >= 0, let stream else { return nil }
        defer { _ = stream.pointee.lpVtbl.pointee.Release(stream) }
        let initHR = bytes.withUnsafeMutableBufferPointer { buf in
            stream.pointee.lpVtbl.pointee.InitializeFromMemory(stream, buf.baseAddress, DWORD(buf.count))
        }
        guard initHR >= 0 else { return nil }

        var decoder: UnsafeMutablePointer<IWICBitmapDecoder>?
        guard factory.pointee.lpVtbl.pointee.CreateDecoderFromStream(
            factory, streamAsIStream(stream), nil,
            WICDecodeMetadataCacheOnLoad, &decoder) >= 0, let decoder else { return nil }
        defer { _ = decoder.pointee.lpVtbl.pointee.Release(decoder) }

        var frame: UnsafeMutablePointer<IWICBitmapFrameDecode>?
        guard decoder.pointee.lpVtbl.pointee.GetFrame(decoder, 0, &frame) >= 0, let frame else { return nil }
        defer { _ = frame.pointee.lpVtbl.pointee.Release(frame) }

        var converter: UnsafeMutablePointer<IWICFormatConverter>?
        guard factory.pointee.lpVtbl.pointee.CreateFormatConverter(factory, &converter) >= 0,
              let converter else { return nil }
        defer { _ = converter.pointee.lpVtbl.pointee.Release(converter) }

        var pf = GUID_WICPixelFormat32bppBGRA
        let source = frameAsBitmapSource(frame)
        guard converter.pointee.lpVtbl.pointee.Initialize(
            converter, source, &pf, WICBitmapDitherTypeNone, nil, 0.0, WICBitmapPaletteTypeCustom) >= 0
        else { return nil }

        var w: UINT = 0, h: UINT = 0
        guard converter.pointee.lpVtbl.pointee.GetSize(converter, &w, &h) >= 0, w > 0, h > 0 else { return nil }
        let width = Int(w), height = Int(h)
        let stride = width * 4
        var buffer = [UInt8](repeating: 0, count: stride * height)
        let copyHR = buffer.withUnsafeMutableBufferPointer { buf in
            converter.pointee.lpVtbl.pointee.CopyPixels(
                converter, nil, UINT(stride), UINT(buf.count), buf.baseAddress)
        }
        guard copyHR >= 0 else { return nil }
        return DecodedImage(width: width, height: height, bgra: buffer)
    }

    /// Build a 32bpp alpha HICON from BGRA pixels via a top-down DIB + zeroed mask.
    static func makeHICON(width: Int, height: Int, bgra: [UInt8]) -> HICON? {
        var bmi = BITMAPINFO()
        bmi.bmiHeader.biSize = DWORD(MemoryLayout<BITMAPINFOHEADER>.size)
        bmi.bmiHeader.biWidth = LONG(width)
        bmi.bmiHeader.biHeight = -LONG(height)   // negative = top-down
        bmi.bmiHeader.biPlanes = 1
        bmi.bmiHeader.biBitCount = 32
        bmi.bmiHeader.biCompression = DWORD(BI_RGB)

        var bits: UnsafeMutableRawPointer?
        guard let color = CreateDIBSection(nil, &bmi, UINT(DIB_RGB_COLORS), &bits, nil, 0),
              let bits else { return nil }
        bgra.withUnsafeBytes { src in
            memcpy(bits, src.baseAddress, min(src.count, width * height * 4))
        }

        // AND mask: 1bpp, word-aligned rows, all zero → alpha channel does the masking.
        let maskStride = ((width + 15) / 16) * 2
        let maskBits = [UInt8](repeating: 0, count: maskStride * height)
        let mask = maskBits.withUnsafeBytes { p in
            CreateBitmap(Int32(width), Int32(height), 1, 1, p.baseAddress)
        }
        defer { if let mask { DeleteObject(mask) }; DeleteObject(color) }

        var ii = ICONINFO()
        ii.fIcon = true
        ii.hbmMask = mask
        ii.hbmColor = color
        return CreateIconIndirect(&ii)
    }

    // COM QueryInterface-free upcasts: these WIC interfaces derive from the expected base, and the
    // Swift-imported vtables are layout-compatible, so a raw reinterpret to the base pointer is valid.
    private static func streamAsIStream(_ s: UnsafeMutablePointer<IWICStream>) -> UnsafeMutablePointer<IStream> {
        UnsafeMutableRawPointer(s).assumingMemoryBound(to: IStream.self)
    }
    private static func frameAsBitmapSource(_ f: UnsafeMutablePointer<IWICBitmapFrameDecode>) -> UnsafeMutablePointer<IWICBitmapSource> {
        UnsafeMutableRawPointer(f).assumingMemoryBound(to: IWICBitmapSource.self)
    }
}
#endif
