import Foundation
import GRDB

/// The calendar date a stored day is shown as.
///
/// Days are keyed by the UTC date their cycle started (`RecordDAO.dayString`),
/// and a cycle starts when its night's sleep does. For anyone who falls asleep
/// before midnight UTC, which in India is every night, that key is the evening
/// before the morning the scores belong to. On screen a day is the local date
/// its main sleep ended, the morning WHOOP's own app files it under. A day with
/// no sleep keeps its key's date.
///
/// Dates are local midnight in `calendar`, so format them in its time zone.
enum DayDates {
    /// Every stored day from `sinceDay` on, or all of them when it's `nil`.
    static func load(_ db: GRDB.Database, sinceDay: String?, calendar: Calendar = .current) throws -> [String: Date] {
        try fetch(db, filter: "(? IS NULL OR d.day >= ?)", arguments: [sinceDay, sinceDay], calendar: calendar)
    }

    /// One stored day, or `nil` when it isn't stored.
    static func date(_ db: GRDB.Database, day: String, calendar: Calendar = .current) throws -> Date? {
        try fetch(db, filter: "d.day = ?", arguments: [day], calendar: calendar)[day]
    }

    /// The key read as a date in `calendar`, for a day nothing else places.
    static func keyDate(_ day: String, calendar: Calendar) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// The main sleep is the one `DailyMetricsBuilder` scores the day from:
    /// the longest non-nap sleep starting within the key's UTC day.
    private static func fetch(_ db: GRDB.Database, filter: String, arguments: StatementArguments, calendar: Calendar) throws -> [String: Date] {
        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT d.day, (
                SELECT s."end" FROM sleeps s
                WHERE s.nap = 0
                  AND s.start >= CAST(strftime('%s', d.day) AS INTEGER)
                  AND s.start < CAST(strftime('%s', d.day) AS INTEGER) + 86400
                ORDER BY (s."end" - s.start) DESC
                LIMIT 1
            ) AS woke_at
            FROM daily_metrics d
            WHERE \(filter)
            """,
            arguments: arguments
        )
        var dates: [String: Date] = [:]
        for row in rows {
            let day: String = row["day"]
            if let wokeAt = row["woke_at"] as Int64? {
                dates[day] = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(wokeAt)))
            } else if let date = keyDate(day, calendar: calendar) {
                dates[day] = date
            }
        }
        return dates
    }
}
