import XCTest
import GRDB
@testable import ReflexWhoop

final class DayDatesTests: XCTestCase {
    private var database: ReflexWhoop.Database!
    private var india = Calendar(identifier: .gregorian)

    override func setUpWithError() throws {
        database = try TestSupport.makeDatabase()
        india.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Kolkata"))
    }

    private func insertDay(_ day: String) throws {
        try database.dbPool.write { db in
            try db.execute(sql: "INSERT INTO daily_metrics (day, algo_version, computed_at) VALUES (?, 1, 0)", arguments: [day])
        }
    }

    private func insertSleep(_ id: String, from start: String, to end: String, nap: Bool = false) throws {
        let formatter = ISO8601DateFormatter()
        let start = try XCTUnwrap(formatter.date(from: start))
        let end = try XCTUnwrap(formatter.date(from: end))
        try database.dbPool.write { db in
            try db.execute(
                sql: #"INSERT INTO sleeps (id, start, "end", nap, score_state, source) VALUES (?, ?, ?, ?, 'SCORED', 'api')"#,
                arguments: [id, Int64(start.timeIntervalSince1970), Int64(end.timeIntervalSince1970), nap]
            )
        }
    }

    private func midnight(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try XCTUnwrap(india.date(from: DateComponents(year: year, month: month, day: day)))
    }

    /// Asleep at 23:02 in India is 17:32 UTC, so the day is keyed the 12th, but
    /// the scores belong to the morning of the 13th.
    func testADayIsTheLocalDateItsMainSleepEnded() throws {
        try insertDay("2026-09-12")
        try insertSleep("night", from: "2026-09-12T23:02:00+05:30", to: "2026-09-13T06:28:00+05:30")

        XCTAssertEqual(try database.dbPool.read { try DayDates.date($0, day: "2026-09-12", calendar: india) }, try midnight(2026, 9, 13))
    }

    func testADayWithoutASleepKeepsItsKeysDate() throws {
        try insertDay("2026-09-10")

        XCTAssertEqual(try database.dbPool.read { try DayDates.date($0, day: "2026-09-10", calendar: india) }, try midnight(2026, 9, 10))
    }

    /// The same sleep `DailyMetricsBuilder` scores the day from: the longest
    /// that isn't a nap.
    func testNapsAndShorterSleepsDontDecideTheDate() throws {
        try insertDay("2026-09-12")
        try insertSleep("night", from: "2026-09-12T23:02:00+05:30", to: "2026-09-13T06:28:00+05:30")
        try insertSleep("short", from: "2026-09-12T18:00:00+05:30", to: "2026-09-12T19:00:00+05:30")
        try insertSleep("nap", from: "2026-09-12T20:00:00+05:30", to: "2026-09-14T12:00:00+05:30", nap: true)

        XCTAssertEqual(try database.dbPool.read { try DayDates.date($0, day: "2026-09-12", calendar: india) }, try midnight(2026, 9, 13))
    }

    func testLoadingARangeResolvesEveryDayFromTheFirst() throws {
        try insertDay("2026-09-10")
        try insertDay("2026-09-12")
        try insertSleep("night", from: "2026-09-12T23:02:00+05:30", to: "2026-09-13T06:28:00+05:30")

        let dates = try database.dbPool.read { try DayDates.load($0, sinceDay: "2026-09-11", calendar: india) }
        XCTAssertEqual(dates, ["2026-09-12": try midnight(2026, 9, 13)])
    }
}
