import XCTest
@testable import ReflexWhoop

final class HistoryRangeTests: XCTestCase {
    func testFirstDayCountsTodayAsDayOne() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-12T12:00:00Z"))
        XCTAssertEqual(HistoryRange.thirtyDays.firstDay(endingOn: now), "2026-08-14")
        XCTAssertEqual(HistoryRange.ninetyDays.firstDay(endingOn: now), "2026-06-15")
        XCTAssertNil(HistoryRange.all.firstDay(endingOn: now))
    }

    func testSpanPhrases() {
        XCTAssertEqual(HistoryRange.thirtyDays.title, "Last 30 days")
        XCTAssertEqual(HistoryRange.year.title, "Last year")
        XCTAssertEqual(HistoryRange.all.title, "All history")
        XCTAssertEqual(HistoryRange.ninetyDays.withinPhrase, "in the last 90 days")
        XCTAssertEqual(HistoryRange.all.withinPhrase, "in all your history")
    }
}
