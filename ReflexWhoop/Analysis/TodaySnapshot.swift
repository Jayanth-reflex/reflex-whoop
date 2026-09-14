import Foundation
import GRDB

/// Everything Today shows, read in one pass for the most recent day WHOOP
/// scored.
struct TodaySnapshot {
    let metrics: DailyMetricsRow
    /// The morning these scores belong to (`DayDates`).
    let date: Date?
    /// The day's cycle is still open, so its strain is still adding up.
    let isCycleInProgress: Bool
    let ranges: [Metric: NormalRange]
    let sleep: LatestSleepDetail?
    let anomalies: [AnomalyRow]
    let lastSyncedAt: Date?

    /// Set when several overnight signals moved together the way they often
    /// do before feeling ill.
    var illnessFlag: AnomalyRow? {
        anomalies.first { $0.kind == AnomalyEngine.Kind.illnessFlag.rawValue }
    }

    func isToday(calendar: Calendar = .current, now: Date = .now) -> Bool {
        date.map { calendar.isDate($0, inSameDayAs: now) } ?? false
    }

    func value(of metric: Metric) -> Double? {
        metrics.value(for: metric)
    }

    func status(of metric: Metric) -> ReadingStatus {
        .classify(value(of: metric), against: ranges[metric])
    }

    static func load(_ db: GRDB.Database, calendar: Calendar = .current) throws -> TodaySnapshot? {
        guard let metrics = try AnalysisQueries.latestDailyMetrics(db) else { return nil }
        return TodaySnapshot(
            metrics: metrics,
            date: try DayDates.date(db, day: metrics.day, calendar: calendar),
            isCycleInProgress: try AnalysisQueries.cycleIsInProgress(db, day: metrics.day),
            ranges: try AnalysisQueries.normalRanges(db, day: metrics.day),
            sleep: try AnalysisQueries.latestSleepDetail(db),
            anomalies: try AnalysisQueries.anomalies(db, day: metrics.day),
            lastSyncedAt: try AnalysisQueries.lastSyncedAt(db)
        )
    }
}
