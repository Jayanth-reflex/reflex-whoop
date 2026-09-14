import Foundation
import GRDB

/// Everything Trends reads for one history range.
struct TrendsContent {
    let histories: [Metric: [MetricPoint]]
    let unusualDayCount: Int
    let patterns: PatternsSummary

    static func load(_ db: GRDB.Database, range: HistoryRange, now: Date) throws -> TrendsContent {
        let firstDay = range.firstDay(endingOn: now)
        return TrendsContent(
            histories: try MetricHistory.points(db, metrics: Metric.allCases, sinceDay: firstDay),
            unusualDayCount: try UnusualDays.count(db, sinceDay: firstDay),
            patterns: PatternsSummary(rows: try AnalysisQueries.correlations(db))
        )
    }
}
