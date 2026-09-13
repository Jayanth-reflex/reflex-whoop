import Foundation
import GRDB

enum UnusualDays {
    /// Newest first.
    static func load(_ db: GRDB.Database, sinceDay: String?) throws -> [UnusualDay] {
        let byDay = Dictionary(grouping: try AnalysisQueries.anomalies(db, sinceDay: sinceDay), by: \.day)
        return try byDay.keys.sorted(by: >).compactMap { day in
            guard let date = RecordDAO.date(forDay: day), let anomalies = byDay[day] else { return nil }
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
                isPossibleIllness: anomalies.contains { $0.kind == AnomalyEngine.Kind.illnessFlag.rawValue },
                readings: readings
            )
        }
    }
}
