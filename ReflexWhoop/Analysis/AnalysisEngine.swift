import Foundation
import GRDB

/// Orchestrates the whole derived layer after a sync: rebuild `daily_metrics`
/// for every dirty day, then baselines/readiness/anomalies (which read the full
/// `daily_metrics` history, not just the dirty days), then a full correlation
/// recompute, then clear `dirty_days`. One write transaction — either the whole
/// pass lands or none of it does, so a crash mid-analysis never leaves
/// `dirty_days` cleared without the derived rows it promised to produce.
enum AnalysisEngine {
    static func run(_ dbPool: DatabasePool) throws {
        try dbPool.write { db in
            let dirtyDays = try String.fetchAll(db, sql: "SELECT DISTINCT day FROM dirty_days ORDER BY day ASC")
            guard !dirtyDays.isEmpty else { return }

            // Pass 1: every dirty day's raw signal lands in daily_metrics first.
            // Baselines below read arbitrary history via "day < D", so a day's
            // predecessors must already be up to date before pass 2 runs — true
            // for previously-analyzed history by construction, and true for a
            // first-ever run (e.g. right after a full backfill) only because this
            // pass runs to completion before pass 2 starts.
            for day in dirtyDays {
                try DailyMetricsBuilder.build(db, day: day)
            }

            for day in dirtyDays {
                try BaselineEngine.compute(db, day: day)
                try ReadinessEngine.compute(db, day: day)
                try AnomalyEngine.compute(db, day: day)
            }

            try CorrelationEngine.recomputeAll(db)

            try db.execute(
                sql: "DELETE FROM dirty_days WHERE day IN (\(dirtyDays.map { _ in "?" }.joined(separator: ",")))",
                arguments: StatementArguments(dirtyDays)
            )
        }
    }
}
