import XCTest
@testable import ReflexWhoop

final class PacketTypeCountsTests: XCTestCase {
    func testRecordsAndSortsByCountDescending() {
        var counts = PacketTypeCounts()
        counts.record(Ble.PacketType.realtimeCompactHR.rawValue)
        counts.record(Ble.PacketType.realtimeCompactHR.rawValue)
        counts.record(Ble.PacketType.event.rawValue)
        let sorted = counts.sortedByCount
        XCTAssertEqual(sorted.first?.packetType, Ble.PacketType.realtimeCompactHR.rawValue)
        XCTAssertEqual(sorted.first?.count, 2)
    }

    func testLabelUsesKnownEnumName() {
        XCTAssertEqual(PacketTypeCounts.label(for: Ble.PacketType.imuA.rawValue), "imuA")
    }

    func testLabelFallsBackToHexForUnknownType() {
        XCTAssertEqual(PacketTypeCounts.label(for: 0x99), "0x99 (unmapped)")
    }
}
