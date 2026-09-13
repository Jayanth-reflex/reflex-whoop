import XCTest
@testable import ReflexWhoop

final class RecordedDayFormatTests: XCTestCase {
    /// Days are stored as midnight UTC. West of UTC that instant is still the
    /// previous evening, so formatting in local time would show the wrong day.
    func testDayNeverShiftsWestOfUTC() throws {
        let day = try XCTUnwrap(RecordDAO.date(forDay: "2026-09-12"))
        var style = Date.FormatStyle.dateTime.day().month(.wide).recordedDay()
        style.locale = Locale(identifier: "en_GB")
        XCTAssertEqual(day.formatted(style), "12 September")

        var local = Date.FormatStyle.dateTime.day().month(.wide)
        local.locale = Locale(identifier: "en_GB")
        local.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        XCTAssertEqual(day.formatted(local), "11 September", "Guards the reason recordedDay() exists")
    }
}
