import Foundation
import GRDB

/// Builds one `daily_metrics` row per dirty day by pulling the day's cycle,
/// recovery, and primary sleep out of the normalized layer. This is where
/// WHOOP's per-record scores become a per-day timeline — no computation happens
/// here beyond picking the right records; the actual analysis (baselines,
/// readiness, correlations) all reads `daily_metrics`, never the normalized
/// tables directly, so it never has to re-derive "which sleep counts as the
/// night for this day" more than once.
enum DailyMetricsBuilder {
    static let algoVersion = 1

    /// UTC day boundaries as epoch seconds, matching `RecordDAO.dayString`'s UTC
    /// bucketing (see its doc comment on the known simplification there).
    private static func dayBounds(_ day: String) -> (start: Int64, end: Int64)? {
        guard let date = RecordDAO.date(forDay: day) else { return nil }
        let start = Int64(date.timeIntervalSince1970)
        return (start, start + 86400)
    }

    @discardableResult
    static func build(_ db: GRDB.Database, day: String) throws -> Bool {
        guard let bounds = dayBounds(day) else { return false }

        let cycle = try Row.fetchOne(
            db, sql: "SELECT id, strain FROM cycles WHERE start >= ? AND start < ? ORDER BY start ASC LIMIT 1",
            arguments: [bounds.start, bounds.end]
        )

        var recovery: Row?
        if let cycleID = cycle?["id"] as String? {
            recovery = try Row.fetchOne(
                db, sql: """
                SELECT recovery_score, hrv_rmssd_milli, resting_heart_rate, spo2_percentage,
                       skin_temp_celsius, user_calibrating
                FROM recoveries WHERE cycle_id = ?
                """,
                arguments: [cycleID]
            )
        }

        // The "primary" sleep for a day is the longest non-nap sleep starting
        // that day — naps are real but shouldn't stand in for the night's sleep
        // in daily trend/correlation analysis.
        let sleep = try Row.fetchOne(
            db, sql: """
            SELECT id, sleep_performance_percentage, respiratory_rate
            FROM sleeps
            WHERE nap = 0 AND start >= ? AND start < ?
            ORDER BY (end - start) DESC LIMIT 1
            """,
            arguments: [bounds.start, bounds.end]
        )

        var sleepDebtMilli: Int64?
        if let sleepID = sleep?["id"] as String? {
            sleepDebtMilli = try Int64.fetchOne(
                db, sql: "SELECT need_from_sleep_debt_milli FROM sleep_need WHERE sleep_id = ?",
                arguments: [sleepID]
            )
        }

        // Nothing to build a row from — don't write a metrics row that's entirely
        // NULL just because e.g. only a workout happened that day.
        guard cycle != nil || recovery != nil || sleep != nil else { return false }

        let signalsPresent = [cycle != nil, recovery != nil, sleep != nil].filter { $0 }.count
        let confidence: Stats.Strength = switch signalsPresent {
        case 3: .strong
        case 2: .moderate
        default: .weak
        }

        try db.execute(
            sql: """
            INSERT INTO daily_metrics
                (day, recovery_score, hrv_rmssd_milli, resting_heart_rate, respiratory_rate,
                 skin_temp_celsius, spo2_percentage, day_strain, sleep_performance_percentage,
                 sleep_debt_milli, readiness_score, algo_version, confidence, computed_at, user_calibrating)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, ?, ?, ?)
            ON CONFLICT(day) DO UPDATE SET
                recovery_score = excluded.recovery_score, hrv_rmssd_milli = excluded.hrv_rmssd_milli,
                resting_heart_rate = excluded.resting_heart_rate, respiratory_rate = excluded.respiratory_rate,
                skin_temp_celsius = excluded.skin_temp_celsius, spo2_percentage = excluded.spo2_percentage,
                day_strain = excluded.day_strain, sleep_performance_percentage = excluded.sleep_performance_percentage,
                sleep_debt_milli = excluded.sleep_debt_milli, algo_version = excluded.algo_version,
                confidence = excluded.confidence, computed_at = excluded.computed_at,
                user_calibrating = excluded.user_calibrating
                -- readiness_score deliberately NOT reset here: BaselineEngine/ReadinessEngine
                -- fills it in as a separate pass over the same row, after this upsert.
            """,
            arguments: [
                day,
                recovery?["recovery_score"] as Double?,
                recovery?["hrv_rmssd_milli"] as Double?,
                recovery?["resting_heart_rate"] as Double?,
                sleep?["respiratory_rate"] as Double?,
                recovery?["skin_temp_celsius"] as Double?,
                recovery?["spo2_percentage"] as Double?,
                cycle?["strain"] as Double?,
                sleep?["sleep_performance_percentage"] as Double?,
                sleepDebtMilli,
                algoVersion,
                confidence.rawValue,
                Int64(Date().timeIntervalSince1970),
                (recovery?["user_calibrating"] as Bool?) ?? false,
            ]
        )
        return true
    }
}
