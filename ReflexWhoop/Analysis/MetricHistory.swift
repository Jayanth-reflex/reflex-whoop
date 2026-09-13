import Foundation
import GRDB

enum MetricHistory {
    /// Days with a value only. A day without one is absent, never zero.
    static func points(_ db: GRDB.Database, metric: Metric, sinceDay: String?) throws -> [MetricPoint] {
        try points(db, metrics: [metric], sinceDay: sinceDay)[metric] ?? []
    }

    /// Several metrics' histories from one read of the daily rows.
    static func points(_ db: GRDB.Database, metrics: [Metric], sinceDay: String?) throws -> [Metric: [MetricPoint]] {
        let rows = try AnalysisQueries.dailyMetrics(db, sinceDay: sinceDay)
        var histories: [Metric: [MetricPoint]] = [:]
        for metric in metrics {
            let ranges = metric.hasNormalRange ? try AnalysisQueries.normalRanges(db, metric: metric, sinceDay: sinceDay) : [:]
            histories[metric] = rows.compactMap { row in
                guard let value = row.value(for: metric), let date = RecordDAO.date(forDay: row.day) else { return nil }
                return MetricPoint(day: row.day, date: date, value: value, range: ranges[row.day])
            }
        }
        return histories
    }
}
