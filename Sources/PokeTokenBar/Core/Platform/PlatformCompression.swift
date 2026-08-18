import Foundation

#if !os(macOS)
import CZlib
#endif

/// Usage-cache snapshot compression — Foundation's `NSData.compressed(using: .zlib)` on macOS,
/// zlib directly on Linux.
///
/// **The two platforms produce different bytes** (Apple's `.zlib` is raw DEFLATE with no header;
/// below is a standard zlib stream with a length prefix). Cache files are machine-local and never
/// travel between platforms, so this does not matter — and even if one did, the caller already
/// falls back to "failed to decompress → treat as plaintext", which costs a cache miss and nothing else.
enum PlatformCompression {
    /// nil on failure — the caller stores plaintext instead (compression is an optimisation,
    /// not a correctness requirement).
    static func compress(_ data: Data) -> Data? {
        #if os(macOS)
        return try? (data as NSData).compressed(using: .zlib) as Data
        #else
        guard !data.isEmpty else { return nil }
        // Prefix the original length as 8 little-endian bytes. zlib's `uncompress` demands the
        // output buffer size up front, and without it you have to retry with a growing buffer —
        // snapshots run to several MB, so that retry cost eats the compression win. Eight bytes
        // removes the problem entirely.
        var bound = compressBound(uLong(data.count))
        var out = Data(count: Int(bound) + 8)
        let status: Int32 = out.withUnsafeMutableBytes { rawOut -> Int32 in
            guard let outBase = rawOut.baseAddress else { return Z_BUF_ERROR }
            var length = UInt64(data.count).littleEndian
            withUnsafeBytes(of: &length) { outBase.copyMemory(from: $0.baseAddress!, byteCount: 8) }
            return data.withUnsafeBytes { rawIn -> Int32 in
                guard let inBase = rawIn.baseAddress else { return Z_BUF_ERROR }
                return compress2(
                    outBase.advanced(by: 8).assumingMemoryBound(to: Bytef.self), &bound,
                    inBase.assumingMemoryBound(to: Bytef.self), uLong(data.count),
                    Z_DEFAULT_COMPRESSION)
            }
        }
        guard status == Z_OK else { return nil }
        return out.prefix(Int(bound) + 8)
        #endif
    }

    /// nil on failure — the caller reads it as an older plaintext cache and decodes the raw bytes.
    static func decompress(_ data: Data) -> Data? {
        #if os(macOS)
        return try? (data as NSData).decompressed(using: .zlib) as Data
        #else
        guard data.count > 8 else { return nil }
        var length: UInt64 = 0
        _ = withUnsafeMutableBytes(of: &length) { data.prefix(8).copyBytes(to: $0) }
        length = UInt64(littleEndian: length)
        // A corrupt or plaintext file can carry an enormous value where the length should be.
        // Trusting it means one damaged cache makes the app allocate gigabytes, so cap it and
        // treat anything above the cap as "not one of ours".
        guard length > 0, length <= 512 * 1024 * 1024 else { return nil }
        let payload = data.suffix(from: data.startIndex + 8)
        var out = Data(count: Int(length))
        var produced = uLongf(length)
        let status: Int32 = out.withUnsafeMutableBytes { rawOut -> Int32 in
            guard let outBase = rawOut.baseAddress else { return Z_BUF_ERROR }
            return payload.withUnsafeBytes { rawIn -> Int32 in
                guard let inBase = rawIn.baseAddress else { return Z_BUF_ERROR }
                return uncompress(
                    outBase.assumingMemoryBound(to: Bytef.self), &produced,
                    inBase.assumingMemoryBound(to: Bytef.self), uLong(payload.count))
            }
        }
        guard status == Z_OK, produced == uLongf(length) else { return nil }
        return out
        #endif
    }
}
