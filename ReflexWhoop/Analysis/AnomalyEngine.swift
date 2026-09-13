import Foundation
import GRDB

/// Two kinds of anomaly, both read off the 60-day baseline z-scores computed by
/// `BaselineEngine`: a combined "you might be getting sick" flag (the classic
/// WHOOP-adjacent signal — respiratory rate and skin temp up, HRV down, RHR up,
/// all at once) and single-metric excursions for anything that's just
/// unusually far from this person's own normal, illness or not.
enum AnomalyEngine {
    static let algoVersion = 1

    /// The `anomalies.kind` values this engine writes.
    enum Kind: String {
        case illnessFlag = "illness_flag"
        case singleMetricExcursion = "single_metric_excursion"
    }

    /// Per-signal threshold for the combined illness flag. Deliberately looser
    /// than the single-metric threshold below (1.5 vs 2.0 SD) — it's the
    /// *combination* of several moderately-unusual signals moving the same
    /// direction that's meaningful, not any one of them alone.
    private static let illnessSignalThreshold = 1.5
    private static let minimumIllnessSignals = 3
    /// Also what the UI calls "unusual" (`ReadingStatus`), so the two agree.
    static let singleMetricThreshold = 2.0
    /// Also the window every normal range on screen uses (`NormalRange`).
    static let baselineWindow = 60

    /// What an illness flag's `detail_json` holds. `triggeredSignals` are
    /// metric columns, in the order the engine checks them.
    struct IllnessDetail: Codable {
        var triggeredSignals: [String]
        var zScores: [String: Double]
    }

    static func compute(_ db: GRDB.Database, day: String) throws {
        // Recomputable derived data: clear this day's anomalies before
        // rewriting, so a re-run (e.g. after a retroactive re-score) doesn't
        // accumulate duplicate rows.
        try db.execute(sql: "DELETE FROM anomalies WHERE day = ?", arguments: [day])

        try detectIllnessFlag(db, day: day)
        try detectSingleMetricExcursions(db, day: day)
    }

    private static func detectIllnessFlag(_ db: GRDB.Database, day: String) throws {
        // (metric, direction) — `.up` means an *increase* beyond baseline counts
        // as a signal, `.down` means a *decrease* does.
        let signals: [(metric: String, direction: Double)] = [
            ("respiratory_rate", 1), ("skin_temp_celsius", 1),
            ("resting_heart_rate", 1), ("hrv_rmssd_milli", -1),
        ]

        var triggered: [String] = []
        var zScores: [String: Double] = [:]
        for (metric, direction) in signals {
            guard let z = try BaselineEngine.zScore(db, metric: metric, day: day, window: baselineWindow) else { continue }
            zScores[metric] = z
            if z * direction >= illnessSignalThreshold {
                triggered.append(metric)
            }
        }

        guard triggered.count >= minimumIllnessSignals else { return }

        let detail = IllnessDetail(triggeredSignals: triggered, zScores: zScores)
        let detailJSON = String(data: try JSONEncoder().encode(detail), encoding: .utf8)

        try db.execute(
            sql: """
            INSERT INTO anomalies (day, kind, metric, z_score, detail_json, algo_version, computed_at)
            VALUES (?, ?, NULL, NULL, ?, ?, ?)
            """,
            arguments: [day, Kind.illnessFlag.rawValue, detailJSON, algoVersion, Int64(Date().timeIntervalSince1970)]
        )
    }

    private static func detectSingleMetricExcursions(_ db: GRDB.Database, day: String) throws {
        for metric in BaselineEngine.metrics {
            guard let z = try BaselineEngine.zScore(db, metric: metric, day: day, window: baselineWindow),
                  abs(z) >= singleMetricThreshold else { continue }

            try db.execute(
                sql: """
                INSERT INTO anomalies (day, kind, metric, z_score, detail_json, algo_version, computed_at)
                VALUES (?, ?, ?, ?, NULL, ?, ?)
                """,
                arguments: [day, Kind.singleMetricExcursion.rawValue, metric, z, algoVersion, Int64(Date().timeIntervalSince1970)]
            )
        }
    }
}
