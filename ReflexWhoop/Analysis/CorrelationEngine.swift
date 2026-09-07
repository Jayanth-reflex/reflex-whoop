import Foundation
import GRDB

/// Lagged correlations against next-day recovery — the analysis WHOOP's own app
/// never surfaces, because it would require looking across days rather than at
/// one score at a time. Recomputed from scratch over the whole history on every
/// run rather than incrementally: a personal WHOOP history tops out at a few
/// hundred days, so a full recompute is milliseconds, and "recompute everything"
/// is much harder to get subtly wrong than "patch in the new correlation."
///
/// Every predictor is tested against the same outcome in the same run, and
/// `Stats.benjaminiHochberg` corrects across all of them together — see its doc
/// comment for why that matters here specifically.
enum CorrelationEngine {
    static let algoVersion = 1
    static let outcome = "next_day_recovery"
    static let lagDays = 1

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private struct SleepInfo {
        var id: String
        var durationMs: Double
        var efficiencyPct: Double?
        var consistencyPct: Double?
        var remPct: Double?
        var swsPct: Double?
        var disturbanceCount: Double?
    }

    private struct DayRow {
        var day: String
        var dayStrain: Double?
        var respiratoryRate: Double?
        var recoveryScore: Double?
    }

    /// Recomputes every predictor's correlation against next-day recovery. Call
    /// this after `daily_metrics` has been rebuilt for any dirty days — cheap
    /// enough to just always run rather than trying to figure out whether any
    /// dirty day could plausibly have shifted a correlation.
    static func recomputeAll(_ db: GRDB.Database) throws {
        let days = try fetchDailyMetricsRows(db)
        guard days.count >= 3 else {
            try db.execute(sql: "DELETE FROM correlations")
            return
        }
        let dayIndex = Dictionary(uniqueKeysWithValues: days.enumerated().map { ($1.day, $0) })
        let sleepByDay = try fetchPrimarySleepByDay(db)
        let acuteChronic = acuteChronicRatios(days)

        // (predictor name, per-day value lookup). Each closure returns the
        // predictor's value on day `i` (index into `days`), or nil if that
        // day doesn't have this signal.
        let predictors: [(name: String, value: (Int) -> Double?)] = [
            ("prior_day_strain", { days[$0].dayStrain }),
            ("respiratory_rate", { days[$0].respiratoryRate }),
            ("acute_chronic_ratio", { acuteChronic[$0] }),
            ("sleep_duration_hours", { sleepByDay[days[$0].day].map { $0.durationMs / 3_600_000 } }),
            ("sleep_efficiency_pct", { sleepByDay[days[$0].day]?.efficiencyPct }),
            ("sleep_consistency_pct", { sleepByDay[days[$0].day]?.consistencyPct }),
            ("rem_sleep_pct", { sleepByDay[days[$0].day]?.remPct }),
            ("slow_wave_sleep_pct", { sleepByDay[days[$0].day]?.swsPct }),
            ("sleep_disturbance_count", { sleepByDay[days[$0].day]?.disturbanceCount }),
        ]

        var results: [(predictor: String, rho: Double, n: Int, pValue: Double)] = []

        for (name, valueAt) in predictors {
            var xs: [Double] = [], ys: [Double] = []
            for i in days.indices {
                guard let nextDay = addOneDay(days[i].day), let j = dayIndex[nextDay] else { continue }
                guard let x = valueAt(i), let y = days[j].recoveryScore else { continue }
                xs.append(x)
                ys.append(y)
            }
            guard let (rho, n) = Stats.spearmanRho(xs, ys), let p = Stats.pValue(rho: rho, n: n) else { continue }
            results.append((name, rho, n, p))
        }

        let corrected = Stats.benjaminiHochberg(results.map(\.pValue))

        try db.execute(sql: "DELETE FROM correlations")
        for (index, result) in results.enumerated() {
            let strength = Stats.strength(rho: result.rho, n: result.n)
            try db.execute(
                sql: """
                INSERT INTO correlations
                    (predictor, outcome, lag_days, rho, n, p_value, p_value_bh_corrected, strength, algo_version, computed_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    result.predictor, outcome, lagDays, result.rho, result.n,
                    result.pValue, corrected[index], strength.rawValue, algoVersion, Int64(Date().timeIntervalSince1970),
                ]
            )
        }
    }

    // MARK: - Data loading

    private static func fetchDailyMetricsRows(_ db: GRDB.Database) throws -> [DayRow] {
        try Row.fetchAll(db, sql: "SELECT day, day_strain, respiratory_rate, recovery_score FROM daily_metrics ORDER BY day ASC")
            .map { DayRow(day: $0["day"], dayStrain: $0["day_strain"], respiratoryRate: $0["respiratory_rate"], recoveryScore: $0["recovery_score"]) }
    }

    /// One row per calendar day: the longest non-nap sleep starting that day,
    /// with its stage percentages. Loaded in two batch queries rather than
    /// per-day lookups — a personal history is at most a few hundred nights, so
    /// this is trivial either way, but batching keeps it obviously correct
    /// (group-by-day logic lives in one place, in Swift, instead of a fragile
    /// correlated subquery).
    private static func fetchPrimarySleepByDay(_ db: GRDB.Database) throws -> [String: SleepInfo] {
        let sleepRows = try Row.fetchAll(
            db, sql: """
            SELECT date(start, 'unixepoch') AS day, id, (end - start) AS duration_s,
                   sleep_efficiency_percentage, sleep_consistency_percentage
            FROM sleeps WHERE nap = 0
            """
        )

        var stageBySleepID: [String: (remMs: Double, swsMs: Double, totalMs: Double, disturbance: Double)] = [:]
        for row in try Row.fetchAll(
            db, sql: """
            SELECT sleep_id, total_rem_sleep_time_milli, total_slow_wave_sleep_time_milli,
                   total_light_sleep_time_milli, disturbance_count
            FROM sleep_stage_summary
            """
        ) {
            let rem = (row["total_rem_sleep_time_milli"] as Double?) ?? 0
            let sws = (row["total_slow_wave_sleep_time_milli"] as Double?) ?? 0
            let light = (row["total_light_sleep_time_milli"] as Double?) ?? 0
            stageBySleepID[row["sleep_id"]] = (rem, sws, rem + sws + light, (row["disturbance_count"] as Double?) ?? 0)
        }

        var bestByDay: [String: SleepInfo] = [:]
        for row in sleepRows {
            let day: String = row["day"]
            let durationMs = ((row["duration_s"] as Double?) ?? 0) * 1000
            guard durationMs > (bestByDay[day]?.durationMs ?? -1) else { continue }

            let stage = stageBySleepID[row["id"] as String]
            bestByDay[day] = SleepInfo(
                id: row["id"],
                durationMs: durationMs,
                efficiencyPct: row["sleep_efficiency_percentage"],
                consistencyPct: row["sleep_consistency_percentage"],
                remPct: stage.flatMap { $0.totalMs > 0 ? $0.remMs / $0.totalMs * 100 : nil },
                swsPct: stage.flatMap { $0.totalMs > 0 ? $0.swsMs / $0.totalMs * 100 : nil },
                disturbanceCount: stage?.disturbance
            )
        }
        return bestByDay
    }

    /// 7-day / 28-day trailing mean day_strain ratio, ending at (and including)
    /// each index — the in-memory equivalent of `ReadinessEngine`'s
    /// `loadBalanceScore`, computed once here over the whole loaded history
    /// instead of per-day database round-trips.
    private static func acuteChronicRatios(_ days: [DayRow]) -> [Double?] {
        let strains = days.map(\.dayStrain)
        var result = [Double?](repeating: nil, count: days.count)
        for i in days.indices {
            let acuteSlice = strains[max(0, i - 6)...i].compactMap { $0 }
            let chronicSlice = strains[max(0, i - 27)...i].compactMap { $0 }
            guard chronicSlice.count >= 14,
                  let acuteMean = Stats.mean(acuteSlice), let chronicMean = Stats.mean(chronicSlice), chronicMean > 0 else { continue }
            result[i] = acuteMean / chronicMean
        }
        return result
    }

    private static func addOneDay(_ day: String) -> String? {
        guard let date = dayFormatter.date(from: day) else { return nil }
        return dayFormatter.string(from: date.addingTimeInterval(86400))
    }
}
