import XCTest
@testable import ReflexWhoop

final class R10DecoderTests: XCTestCase {
    private func f32LEBytes(_ value: Float) -> [UInt8] {
        withUnsafeBytes(of: value.bitPattern.littleEndian) { Array($0) }
    }

    private func makeInner(packetType: UInt8 = 0x2B, hr: UInt8 = 70, rrCount: UInt8 = 0, rr: [Int16] = [], accel: (Float, Float, Float) = (0, 0, 1)) -> Data {
        var b = [UInt8](repeating: 0, count: 48)
        b[0] = packetType
        b[17] = hr
        b[18] = rrCount
        var offset = 19
        for value in rr {
            let bytes = withUnsafeBytes(of: value.littleEndian) { Array($0) }
            b[offset] = bytes[0]
            b[offset + 1] = bytes[1]
            offset += 2
        }
        let (x, y, z) = accel
        b.replaceSubrange(36..<40, with: f32LEBytes(x))
        b.replaceSubrange(40..<44, with: f32LEBytes(y))
        b.replaceSubrange(44..<48, with: f32LEBytes(z))
        return Data(b)
    }

    func testPlausibleRestingSampleDecodes() {
        let inner = makeInner(hr: 70, accel: (0, 0, 1))
        let sample = R10Decoder.decode(inner: inner)
        XCTAssertEqual(sample?.candidateHrBpm, 70)
        XCTAssertEqual(sample?.accelMagnitudeG ?? 0, 1.0, accuracy: 0.001)
        XCTAssertTrue(sample?.isPlausible ?? false)
    }

    func testImplausibleHrStillDecodesButNotPlausible() {
        let inner = makeInner(hr: 250, accel: (0, 0, 1))
        let sample = R10Decoder.decode(inner: inner)
        XCTAssertNotNil(sample)
        XCTAssertFalse(sample?.isPlausible ?? true)
    }

    func testImplausibleAccelMagnitudeNotPlausible() {
        let inner = makeInner(hr: 70, accel: (10, 10, 10))
        let sample = R10Decoder.decode(inner: inner)
        XCTAssertFalse(sample?.isPlausible ?? true)
    }

    func testDecodesRrIntervals() {
        let inner = makeInner(hr: 70, rrCount: 2, rr: [800, 820], accel: (0, 0, 1))
        let sample = R10Decoder.decode(inner: inner)
        XCTAssertEqual(sample?.rrIntervalsMs, [800, 820])
        XCTAssertTrue(sample?.isPlausible ?? false)
    }

    func testOutOfRangeRrIntervalMarksImplausible() {
        let inner = makeInner(hr: 70, rrCount: 1, rr: [50], accel: (0, 0, 1))
        let sample = R10Decoder.decode(inner: inner)
        XCTAssertFalse(sample?.isPlausible ?? true)
    }

    func testWrongPacketTypeReturnsNil() {
        let inner = makeInner(packetType: 0x28)
        XCTAssertNil(R10Decoder.decode(inner: inner))
    }

    func testTooShortReturnsNil() {
        XCTAssertNil(R10Decoder.decode(inner: Data([0x2B, 0x00])))
    }
}
