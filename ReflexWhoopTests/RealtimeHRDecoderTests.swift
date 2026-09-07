import XCTest
@testable import ReflexWhoop

final class RealtimeHRDecoderTests: XCTestCase {
    // A real captured 0x28 inner packet from docs/PROTOCOL-GEN5.md's session 2
    // (seq 6290): byte[8] = 0x53 = 83 bpm, a plausible resting-adjacent reading.
    private let realInner = Data([
        0x28, 0x02, 0xb7, 0xe2, 0x9e, 0x6a, 0xb8, 0x7e,
        0x53, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x01, 0x00,
    ])

    func testDecodesHeartRateFromARealCapturedRecord() {
        XCTAssertEqual(RealtimeHRDecoder.heartRateBpm(inner: realInner), 83)
    }

    func testReturnsNilForWrongPacketType() {
        var other = realInner
        other[0] = 0x24
        XCTAssertNil(RealtimeHRDecoder.heartRateBpm(inner: other))
    }

    func testReturnsNilForTooShortInput() {
        XCTAssertNil(RealtimeHRDecoder.heartRateBpm(inner: Data([0x28, 0x02, 0x00])))
    }

    func testReturnsNilForEmptyInput() {
        XCTAssertNil(RealtimeHRDecoder.heartRateBpm(inner: Data()))
    }
}
