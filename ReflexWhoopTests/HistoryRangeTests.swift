import XCTest
@testable import ReflexWhoop

final class HistoryRangeTests: XCTestCase {
    func testFirstDayCountsTodayAsDayOne() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-12T12:00:00Z"))
        XCTAssertEqual(HistoryRange.thirtyDays.firstDay(endingOn: now), "2026-08-14")
        XCTAssertEqual(HistoryRange.ninetyDays.firstDay(endingOn: now), "2026-06-15")
        XCTAssertNil(HistoryRange.all.firstDay(endingOn: now))
    }
}
