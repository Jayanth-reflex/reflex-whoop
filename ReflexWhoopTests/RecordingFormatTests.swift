import XCTest
@testable import ReflexWhoop

final class RecordingFormatTests: XCTestCase {
    private let locale = Locale(identifier: "en_GB")

    private func calendar() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Kolkata"))
        return calendar
    }

    private func date(_ iso: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: iso))
    }

    func testStartNamesTodayAndYesterday() throws {
        let now = try date("2026-09-13T20:00:00+05:30")
        let calendar = try calendar()
        XCTAssertEqual(RecordingFormat.start(try date("2026-09-13T14:11:00+05:30"), calendar: calendar, now: now, locale: locale), "Today, 14:11")
        XCTAssertEqual(RecordingFormat.start(try date("2026-09-12T19:53:00+05:30"), calendar: calendar, now: now, locale: locale), "Yesterday, 19:53")
        let older = RecordingFormat.start(try date("2026-09-10T18:13:00+05:30"), calendar: calendar, now: now, locale: locale)
        XCTAssertTrue(older.hasPrefix("Thu 10 Sep"), older)
        XCTAssertTrue(older.hasSuffix(", 18:13"), older)
    }

    func testLengthSaysWhyThereIsNone() {
        func recording(first: TimeInterval?, last: TimeInterval?) -> RecordingSummary {
            RecordingSummary(
                id: "r",
                startedAt: Date(timeIntervalSince1970: 0),
                firstReadingAt: first.map(Date.init(timeIntervalSince1970:)),
                lastReadingAt: last.map(Date.init(timeIntervalSince1970:)),
                minutesWithReadings: 0,
                readingCount: 0,
                averageBpm: nil,
                lowestBpm: nil,
                highestBpm: nil
            )
        }
        XCTAssertEqual(RecordingFormat.length(of: recording(first: nil, last: nil)), "Nothing captured")
        XCTAssertEqual(RecordingFormat.length(of: recording(first: 0, last: 30)), "Under a minute")
        XCTAssertEqual(RecordingFormat.length(of: recording(first: 0, last: 4260)), "1h 11m")
    }
}
