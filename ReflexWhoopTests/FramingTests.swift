import XCTest
@testable import ReflexWhoop

final class FramingTests: XCTestCase {
    private let check123456789 = Array("123456789".utf8)

    // These two check the CRC algorithms themselves against the standard
    // textbook check values — true regardless of whether Gen5Envelope's field
    // layout hypothesis is right, since they don't involve WHOOP's protocol.
    func testCrc16ModbusMatchesStandardCheckValue() {
        XCTAssertEqual(Crc.modbus16(check123456789), 0x4B37)
    }

    func testCrc32IeeeMatchesStandardCheckValue() {
        XCTAssertEqual(Crc.ieee32(check123456789), 0xCBF4_3926)
    }

    func testCrcOfEmptyInputDoesNotCrash() {
        XCTAssertEqual(Crc.modbus16([]), 0xFFFF)
        XCTAssertEqual(Crc.ieee32([]), 0)
    }

    // Gen5Envelope's layout is a documented hypothesis (see its doc comment) —
    // these tests only assert internal self-consistency (encode then decode
    // recovers what was encoded, and a corrupted byte is caught by CRC), not
    // that the hypothesis matches the real band.
    func testEncodeThenDecodeRoundTripsWithValidCrcs() {
        let inner = Data([0x23, 0x01, 0x23]) // command / seq / GET_HELLO_HARVARD
        let frame = Gen5Envelope.encode(field: 0, inner: inner)
        guard let decoded = Gen5Envelope.decode(frame) else {
            return XCTFail("decode returned nil for a freshly-encoded frame")
        }
        XCTAssertTrue(decoded.headerCrcValid)
        XCTAssertTrue(decoded.trailerCrcValid)
        // inner is padded to a multiple of 4; the unpadded prefix must match.
        XCTAssertEqual(decoded.inner.prefix(inner.count), inner)
    }

    func testDecodeDetectsCorruptedTrailer() {
        let inner = Data([0x23, 0x01, 0x1A])
        var frame = Gen5Envelope.encode(field: 0, inner: inner)
        frame[frame.count - 1] ^= 0xFF // flip a bit in the CRC-32 trailer
        guard let decoded = Gen5Envelope.decode(frame) else {
            return XCTFail("decode should still parse the header even with a bad trailer")
        }
        XCTAssertTrue(decoded.headerCrcValid)
        XCTAssertFalse(decoded.trailerCrcValid)
    }

    func testDecodeDetectsCorruptedHeader() {
        let inner = Data([0x23, 0x01, 0x1A])
        var frame = Gen5Envelope.encode(field: 0, inner: inner)
        frame[5] ^= 0xFF // flip a bit in the CRC-16 header field
        guard let decoded = Gen5Envelope.decode(frame) else {
            return XCTFail("decode should still return a candidate to report the mismatch")
        }
        XCTAssertFalse(decoded.headerCrcValid)
    }

    func testDecodeRejectsTooShortInput() {
        XCTAssertNil(Gen5Envelope.decode(Data([0xAA, 0x01, 0x00])))
    }

    func testDecodeRejectsWrongMarker() {
        let inner = Data([0x23, 0x01, 0x1A])
        var frame = Gen5Envelope.encode(field: 0, inner: inner)
        frame[0] = 0x00
        XCTAssertNil(Gen5Envelope.decode(frame))
    }

    // MARK: - FrameReassembler

    func testReassemblerReconstructsAFrameSplitAcrossManyFragments() {
        let inner = Data([0x24, 0x01, 0x23, 0xDE, 0xAD, 0xBE, 0xEF])
        let frame = Gen5Envelope.encode(field: 0, inner: inner)

        let reassembler = FrameReassembler()
        var collected: [Gen5Envelope.Frame] = []
        // Simulate a 20-byte BLE MTU chopping one logical frame into pieces.
        for chunk in stride(from: 0, to: frame.count, by: 5) {
            let end = min(chunk + 5, frame.count)
            collected += reassembler.feed(frame.subdata(in: chunk..<end))
        }
        XCTAssertEqual(collected.count, 1)
        XCTAssertTrue(collected[0].headerCrcValid)
        XCTAssertTrue(collected[0].trailerCrcValid)
    }

    func testReassemblerHandlesTwoConsecutiveFramesInOneFeed() {
        let frameA = Gen5Envelope.encode(field: 0, inner: Data([0x24, 0x01, 0x1A]))
        let frameB = Gen5Envelope.encode(field: 0, inner: Data([0x24, 0x02, 0x22]))
        let reassembler = FrameReassembler()
        let collected = reassembler.feed(frameA + frameB)
        XCTAssertEqual(collected.count, 2)
        XCTAssertTrue(collected.allSatisfy { $0.headerCrcValid && $0.trailerCrcValid })
    }

    func testReassemblerResyncsPastAStrayMarkerByteInSensorNoise() {
        // A 0xAA byte inside unrelated sensor noise, followed by a real frame —
        // per docs/design.md this is exactly the case length-based reassembly
        // must survive rather than getting stuck on the wrong start.
        let noise = Data([0x01, 0xAA, 0x02, 0x03]) // 0xAA here is not a real frame start
        let real = Gen5Envelope.encode(field: 0, inner: Data([0x24, 0x01, 0x1A]))
        let reassembler = FrameReassembler()
        let collected = reassembler.feed(noise + real)
        XCTAssertEqual(collected.count, 1)
        XCTAssertTrue(collected[0].headerCrcValid)
    }
}
