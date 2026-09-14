import Foundation
import GRDB

enum UnusualDays {
    /// How many days `load` would return, without reading each day's values.
    static func count(_ db: GRDB.Database, sinceDay: String?) throws -> Int {
        try Int.fetchOne(
            db,
            sql: "SELECT COUNT(DISTINCT day) FROM anomalies WHERE (? IS NULL OR day >= ?)",
            arguments: [sinceDay, sinceDay]
        ) ?? 0
    }

    /// Newest first.
    static func load(_ db: GRDB.Database, sinceDay: String?) throws -> [UnusualDay] {
        let byDay = Dictionary(grouping: try AnalysisQueries.anomalies(db, sinceDay: sinceDay, limit: nil), by: \.day)
        let dates = try DayDates.load(db, sinceDay: sinceDay)
        return try byDay.keys.sorted(by: >).compactMap { day in
            guard let date = dates[day] ?? DayDates.keyDate(day, calendar: .current), let anomalies = byDay[day] else { return nil }
            let metrics = try DailyMetricsRow.fetchOne(db, sql: "SELECT * FROM daily_metrics WHERE day = ?", arguments: [day])
            let ranges = try AnalysisQueries.normalRanges(db, day: day)
            let readings = anomalies.compactMap { anomaly -> UnusualReading? in
                guard anomaly.kind == AnomalyEngine.Kind.singleMetricExcursion.rawValue,
                      let metric = anomaly.metric.flatMap(Metric.init(column:)),
                      let value = metrics?.value(for: metric),
                      let range = ranges[metric] else { return nil }
                return UnusualReading(metric: metric, value: value, range: range)
            }
            return UnusualDay(
                day: day,
                date: date,
                illnessSignals: anomalies.first { $0.kind == AnomalyEngine.Kind.illnessFlag.rawValue }?.illnessSignals,
                readings: readings
            )
        }
    }
}
