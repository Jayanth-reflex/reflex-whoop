import XCTest
@testable import ReflexWhoop

/// Per docs/PROTOCOL-GEN5.md's "Safety rails": these two tables are
/// the actual safety mechanism (the envelope/decoder guesses elsewhere are not).
/// Every opcode named in the design doc must land on the correct side, the two
/// sides must never overlap, and a value outside both tables must still be
/// rejected — this test is the thing that's supposed to fail loudly if a future
/// edit to `BleConstants.swift` ever moves an opcode to the wrong list.
final class OpcodeAllowlistTests: XCTestCase {
    func testEveryAllowedOpcodePassesAssertAllowed() {
        for opcode in Ble.AllowedOpcode.allCases {
            XCTAssertNoThrow(try OpcodeAllowlist.assertAllowed(opcode.rawValue), "0x\(String(opcode.rawValue, radix: 16)) should be allowed")
            XCTAssertTrue(OpcodeAllowlist.isAllowed(opcode.rawValue))
        }
    }

    func testEveryForbiddenOpcodeIsRejected() {
        for opcode in Ble.ForbiddenOpcode.allCases {
            XCTAssertThrowsError(try OpcodeAllowlist.assertAllowed(opcode.rawValue), "0x\(String(opcode.rawValue, radix: 16)) must never be sendable") { error in
                XCTAssertTrue(error is OpcodeAllowlist.ForbiddenOpcodeError)
            }
            XCTAssertFalse(OpcodeAllowlist.isAllowed(opcode.rawValue))
        }
    }

    func testAllowedAndForbiddenSetsAreDisjoint() {
        let allowedValues = Set(Ble.AllowedOpcode.allCases.map(\.rawValue))
        let forbiddenValues = Set(Ble.ForbiddenOpcode.allCases.map(\.rawValue))
        XCTAssertTrue(allowedValues.isDisjoint(with: forbiddenValues))
    }

    func testUnknownOpcodeIsRejectedNotJustUnlistedOnes() {
        // 0xFF isn't in either table in docs/PROTOCOL-GEN5.md — must fail closed.
        XCTAssertThrowsError(try OpcodeAllowlist.assertAllowed(0xFF))
        XCTAssertFalse(OpcodeAllowlist.isAllowed(0xFF))
    }

    func testDesignDocTableMatchesExactly() {
        // Transcribed from docs/PROTOCOL-GEN5.md's two opcode tables — if this drifts
        // from that doc, one of them is wrong.
        let expectedAllowed: Set<UInt8> = [0x23, 0x1A, 0x22, 0x03, 0x3F, 0x6A, 0x6B, 0x6C]
        let expectedForbidden: Set<UInt8> = [0x16, 0x17, 0x21, 0x14, 0x9A, 0x1D, 0x0A]
        XCTAssertEqual(Set(Ble.AllowedOpcode.allCases.map(\.rawValue)), expectedAllowed)
        XCTAssertEqual(Set(Ble.ForbiddenOpcode.allCases.map(\.rawValue)), expectedForbidden)
    }

    func testMustNeverAckHistoricalAndSyncMarkerPacketTypes() {
        XCTAssertTrue(OpcodeAllowlist.mustNeverAck(packetType: Ble.PacketType.historical.rawValue))
        XCTAssertTrue(OpcodeAllowlist.mustNeverAck(packetType: Ble.PacketType.syncMarker.rawValue))
        XCTAssertFalse(OpcodeAllowlist.mustNeverAck(packetType: Ble.PacketType.event.rawValue))
    }
}
