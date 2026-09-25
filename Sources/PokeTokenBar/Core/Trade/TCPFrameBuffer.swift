import Foundation

/// TCP is a stream, so it has no message boundaries — frame with a 4-byte big-endian length
/// prefix. MultipeerConnectivity guarantees message-level delivery so it doesn't need this
/// framing — this is ManualTradeTransport(TCP)-only.
struct TCPFrameBuffer {
    /// Upper bound on a frame's payload length — the peer is an arbitrary IP:port the user typed
    /// in by hand, so it can't be trusted, and a manipulated length prefix (e.g. 0xFFFFFFFF)
    /// would grow the buffer without bound if there were no cap. The real TradeMessage (JSON)
    /// stays within a few hundred bytes, so this is set generously, the same way as
    /// SaveTransfer.maxFileBytes.
    static let maxFrameLength = 1 * 1024 * 1024

    enum FrameError: Error, Equatable {
        case frameTooLarge(length: Int, limit: Int)
    }

    private var buffer = Data()

    static func frame(_ payload: Data) -> Data {
        var length = UInt32(payload.count).bigEndian
        var framed = Data(bytes: &length, count: 4)
        framed.append(payload)
        return framed
    }

    /// Accumulates newly arrived bytes and returns every completed frame extracted so far
    /// (a partial frame stays in the buffer). Throws if the length prefix exceeds the cap — the
    /// caller must treat this as a connection close, not a silent stall.
    mutating func append(_ data: Data) throws -> [Data] {
        buffer.append(data)
        var frames: [Data] = []
        while buffer.count >= 4 {
            let lengthPrefix = buffer.prefix(4)
            let length = Int(UInt32(bigEndian: lengthPrefix.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }))
            guard length <= Self.maxFrameLength else {
                throw FrameError.frameTooLarge(length: length, limit: Self.maxFrameLength)
            }
            guard buffer.count >= 4 + length else { break }
            let frameStart = buffer.startIndex + 4
            let frameEnd = frameStart + length
            frames.append(buffer.subdata(in: frameStart..<frameEnd))
            buffer.removeSubrange(buffer.startIndex..<frameEnd)
        }
        return frames
    }
}
