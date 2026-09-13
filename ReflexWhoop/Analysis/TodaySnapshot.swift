import Foundation
import GRDB

/// Everything Today shows, read in one pass for the most recent day WHOOP
/// scored.
struct TodaySnapshot {
    let metrics: DailyMetricsRow
    let ranges: [Metric: NormalRange]
    let sleep: LatestSleepDetail?
    let anomalies: [AnomalyRow]
    let lastSyncedAt: Date?

    /// Set when several overnight signals moved together the way they often
    /// do before feeling ill.
    var illnessFlag: AnomalyRow? {
        anomalies.first { $0.kind == AnomalyEngine.Kind.illnessFlag.rawValue }
    }

    func value(of metric: Metric) -> Double? {
        metrics.value(for: metric)
    }

    func status(of metric: Metric) -> ReadingStatus {
        .classify(value(of: metric), against: ranges[metric])
    }

    static func load(_ db: GRDB.Database) throws -> TodaySnapshot? {
        guard let metrics = try AnalysisQueries.latestDailyMetrics(db) else { return nil }
        return TodaySnapshot(
            metrics: metrics,
            ranges: try AnalysisQueries.normalRanges(db, day: metrics.day),
            sleep: try AnalysisQueries.latestSleepDetail(db),
            anomalies: try AnalysisQueries.anomalies(db, day: metrics.day),
            lastSyncedAt: try AnalysisQueries.lastSyncedAt(db)
        )
    }
}
