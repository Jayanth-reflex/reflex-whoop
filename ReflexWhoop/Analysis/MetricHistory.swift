import Foundation
import GRDB

enum MetricHistory {
    /// Days with a value only. A day without one is absent, never zero.
    static func points(_ db: GRDB.Database, metric: Metric, sinceDay: String?) throws -> [MetricPoint] {
        let ranges = metric.hasNormalRange ? try AnalysisQueries.normalRanges(db, metric: metric, sinceDay: sinceDay) : [:]
        return try AnalysisQueries.dailyMetrics(db, sinceDay: sinceDay).compactMap { row in
            guard let value = row.value(for: metric), let date = RecordDAO.date(forDay: row.day) else { return nil }
            return MetricPoint(day: row.day, date: date, value: value, range: ranges[row.day])
        }
    }
}
