import XCTest
@testable import PokeTokenBar

final class TCPFrameBufferTests: XCTestCase {
    func testSingleFrameArrivingWhole() throws {
        var buffer = TCPFrameBuffer()
        let payload = Data("hello".utf8)
        XCTAssertEqual(try buffer.append(TCPFrameBuffer.frame(payload)), [payload])
    }

    func testFrameSplitAcrossTwoAppends() throws {
        var buffer = TCPFrameBuffer()
        let framed = TCPFrameBuffer.frame(Data("hello".utf8))
        let firstHalf = Data(framed.prefix(3))
        let secondHalf = Data(framed.suffix(from: 3))
        XCTAssertTrue(try buffer.append(firstHalf).isEmpty)
        XCTAssertEqual(try buffer.append(secondHalf), [Data("hello".utf8)])
    }

    func testTwoFramesArrivingTogether() throws {
        var buffer = TCPFrameBuffer()
        var combined = TCPFrameBuffer.frame(Data("a".utf8))
        combined.append(TCPFrameBuffer.frame(Data("bb".utf8)))
        XCTAssertEqual(try buffer.append(combined), [Data("a".utf8), Data("bb".utf8)])
    }

    func testEmptyPayloadRoundTrips() throws {
        var buffer = TCPFrameBuffer()
        XCTAssertEqual(try buffer.append(TCPFrameBuffer.frame(Data())), [Data()])
    }

    /// The length prefix (4 bytes) has fully arrived but the payload has only partially arrived —
    /// knowing the length must not trigger an immediate cut; it must wait until the whole payload arrives.
    func testPayloadArrivesSplitAfterCompleteLengthPrefix() throws {
        var buffer = TCPFrameBuffer()
        let framed = TCPFrameBuffer.frame(Data("hello".utf8))
        let prefixPlusPartialPayload = Data(framed.prefix(6))
        let remainingPayload = Data(framed.suffix(from: 6))
        XCTAssertTrue(try buffer.append(prefixPlusPartialPayload).isEmpty)
        XCTAssertEqual(try buffer.append(remainingPayload), [Data("hello".utf8)])
    }

    /// The length prefix (4 bytes) itself arrives split into two chunks — the first chunk alone
    /// isn't enough to know the frame length.
    func testLengthPrefixItselfArrivesSplit() throws {
        var buffer = TCPFrameBuffer()
        let framed = TCPFrameBuffer.frame(Data("hello".utf8))
        let firstTwoBytes = Data(framed.prefix(2))
        let remainder = Data(framed.suffix(from: 2))
        XCTAssertTrue(try buffer.append(firstTwoBytes).isEmpty)
        XCTAssertEqual(try buffer.append(remainder), [Data("hello".utf8)])
    }

    /// Verifies the next frame is cut correctly even when a frame was already consumed before this
    /// subdata(in:)/removeSubrange(_:), so the buffer's internal index doesn't start at 0 — a
    /// missing index offset would lead to a crash or corrupted data.
    func testThirdFrameAfterTwoPriorFramesConsumed() throws {
        var buffer = TCPFrameBuffer()
        var combined = TCPFrameBuffer.frame(Data("a".utf8))
        combined.append(TCPFrameBuffer.frame(Data("bb".utf8)))
        combined.append(TCPFrameBuffer.frame(Data("ccc".utf8)))
        XCTAssertEqual(try buffer.append(combined), [Data("a".utf8), Data("bb".utf8), Data("ccc".utf8)])
    }

    /// R23 — a manipulated length prefix (a value exceeding the cap) must throw instead of causing
    /// unbounded buffer growth. The peer is an arbitrary IP:port the user typed in themselves, so
    /// this length value cannot be trusted.
    func testLengthExceedingCapThrows() {
        var buffer = TCPFrameBuffer()
        var oversizedLength = UInt32(TCPFrameBuffer.maxFrameLength + 1).bigEndian
        let malformedPrefix = Data(bytes: &oversizedLength, count: 4)
        XCTAssertThrowsError(try buffer.append(malformedPrefix)) { error in
            XCTAssertEqual(error as? TCPFrameBuffer.FrameError,
                            .frameTooLarge(length: TCPFrameBuffer.maxFrameLength + 1, limit: TCPFrameBuffer.maxFrameLength))
        }
    }

    /// A length within the cap must pass normally — verifies R23's guard isn't overly strict.
    func testLengthAtCapIsAccepted() throws {
        var buffer = TCPFrameBuffer()
        let payload = Data(repeating: 0, count: TCPFrameBuffer.maxFrameLength)
        XCTAssertEqual(try buffer.append(TCPFrameBuffer.frame(payload)), [payload])
    }
}
