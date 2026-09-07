import Foundation
import GRDB

/// Rolling 30/60-day baselines per metric: mean, stddev, and today's z-score
/// against that trailing window. The window is the N days strictly *before* the
/// target day, not including it — a day's own value must never pull its own
/// baseline toward itself, or "how does today compare to normal" stops meaning
/// anything.
enum BaselineEngine {
    static let algoVersion = 1

    /// Below this many trailing days, a mean/stddev is closer to noise than a
    /// baseline. No row is written rather than publishing one built on 2 points.
    private static let minimumSampleSize = 5

    static let windows = [30, 60]

    static let metrics = [
        "recovery_score", "hrv_rmssd_milli", "resting_heart_rate",
        "respiratory_rate", "skin_temp_celsius", "spo2_percentage",
    ]

    static func compute(_ db: GRDB.Database, day: String) throws {
        guard let todayRow = try Row.fetchOne(db, sql: "SELECT * FROM daily_metrics WHERE day = ?", arguments: [day]) else {
            return
        }

        for metric in metrics {
            guard let todayValue = todayRow[metric] as Double? else { continue }

            for window in windows {
                let history = try Double.fetchAll(
                    db, sql: """
                    SELECT \(metric) FROM daily_metrics
                    WHERE day < ? AND user_calibrating = 0 AND \(metric) IS NOT NULL
                    ORDER BY day DESC LIMIT ?
                    """,
                    arguments: [day, window]
                )
                guard history.count >= minimumSampleSize,
                      let mean = Stats.mean(history), let stddev = Stats.stddev(history) else {
                    continue
                }
                let z = Stats.zScore(value: todayValue, mean: mean, stddev: stddev)

                try db.execute(
                    sql: """
                    INSERT INTO baselines (metric, day, window_days, mean_val, stddev_val, z_score,
                                            excluded_calibrating, algo_version, computed_at)
                    VALUES (?, ?, ?, ?, ?, ?, 1, ?, ?)
                    ON CONFLICT(metric, day, window_days) DO UPDATE SET
                        mean_val = excluded.mean_val, stddev_val = excluded.stddev_val,
                        z_score = excluded.z_score, algo_version = excluded.algo_version,
                        computed_at = excluded.computed_at
                    """,
                    arguments: [metric, day, window, mean, stddev, z, algoVersion, Int64(Date().timeIntervalSince1970)]
                )
            }
        }
    }

    /// Convenience read used by Readiness/Anomaly engines and the UI: the
    /// 60-day z-score for one metric on one day, or `nil` if there wasn't enough
    /// history to compute one.
    static func zScore(_ db: GRDB.Database, metric: String, day: String, window: Int = 60) throws -> Double? {
        try Double.fetchOne(
            db, sql: "SELECT z_score FROM baselines WHERE metric = ? AND day = ? AND window_days = ?",
            arguments: [metric, day, window]
        )
    }
}
