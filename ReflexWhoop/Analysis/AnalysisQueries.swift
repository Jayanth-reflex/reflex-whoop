import Foundation
import GRDB

/// Read-side of the derived layer — every query the UI needs, in one place, so
/// views stay dumb (fetch, display) instead of each growing its own SQL.

struct DailyMetricsRow: Decodable, FetchableRecord, Identifiable {
    var id: String { day }
    var day: String
    var recoveryScore: Double?
    var hrvRmssdMilli: Double?
    var restingHeartRate: Double?
    var respiratoryRate: Double?
    var skinTempCelsius: Double?
    var spo2Percentage: Double?
    var dayStrain: Double?
    var sleepPerformancePercentage: Double?
    var sleepDebtMilli: Int64?
    var readinessScore: Double?
    var confidence: String?
    var userCalibrating: Bool

    enum CodingKeys: String, CodingKey {
        case day
        case recoveryScore = "recovery_score"
        case hrvRmssdMilli = "hrv_rmssd_milli"
        case restingHeartRate = "resting_heart_rate"
        case respiratoryRate = "respiratory_rate"
        case skinTempCelsius = "skin_temp_celsius"
        case spo2Percentage = "spo2_percentage"
        case dayStrain = "day_strain"
        case sleepPerformancePercentage = "sleep_performance_percentage"
        case sleepDebtMilli = "sleep_debt_milli"
        case readinessScore = "readiness_score"
        case confidence
        case userCalibrating = "user_calibrating"
    }

    func value(for metric: Metric) -> Double? {
        switch metric {
        case .recovery: recoveryScore
        case .strain: dayStrain
        case .sleepPerformance: sleepPerformancePercentage
        case .heartRateVariability: hrvRmssdMilli
        case .restingHeartRate: restingHeartRate
        case .breathingRate: respiratoryRate
        case .skinTemperature: skinTempCelsius
        case .bloodOxygen: spo2Percentage
        }
    }

    /// Pulls a metric's value by its column name — lets `TrendsView`'s metric
    /// picker stay data-driven instead of a hardcoded switch per chart.
    func value(for metric: TrendMetric) -> Double? {
        switch metric {
        case .recoveryScore: recoveryScore
        case .hrvRmssdMilli: hrvRmssdMilli
        case .restingHeartRate: restingHeartRate
        case .respiratoryRate: respiratoryRate
        case .skinTempCelsius: skinTempCelsius
        case .spo2Percentage: spo2Percentage
        case .dayStrain: dayStrain
        case .sleepPerformancePercentage: sleepPerformancePercentage
        case .readinessScore: readinessScore
        }
    }
}

enum TrendMetric: String, CaseIterable, Identifiable {
    case recoveryScore, hrvRmssdMilli, restingHeartRate, respiratoryRate
    case skinTempCelsius, spo2Percentage, dayStrain, sleepPerformancePercentage, readinessScore

    var id: String { rawValue }

    var columnName: String {
        switch self {
        case .recoveryScore: "recovery_score"
        case .hrvRmssdMilli: "hrv_rmssd_milli"
        case .restingHeartRate: "resting_heart_rate"
        case .respiratoryRate: "respiratory_rate"
        case .skinTempCelsius: "skin_temp_celsius"
        case .spo2Percentage: "spo2_percentage"
        case .dayStrain: "day_strain"
        case .sleepPerformancePercentage: "sleep_performance_percentage"
        case .readinessScore: "readiness_score"
        }
    }

    var label: String {
        switch self {
        case .recoveryScore: "Recovery"
        case .hrvRmssdMilli: "HRV"
        case .restingHeartRate: "Resting HR"
        case .respiratoryRate: "Respiratory Rate"
        case .skinTempCelsius: "Skin Temp"
        case .spo2Percentage: "SpO2"
        case .dayStrain: "Strain"
        case .sleepPerformancePercentage: "Sleep Performance"
        case .readinessScore: "Readiness"
        }
    }

    var unit: String {
        switch self {
        case .recoveryScore, .spo2Percentage, .sleepPerformancePercentage, .readinessScore: "%"
        case .hrvRmssdMilli: "ms"
        case .restingHeartRate: "bpm"
        case .respiratoryRate: "rpm"
        case .skinTempCelsius: "°C"
        case .dayStrain: ""
        }
    }

    /// Whether `BaselineEngine` tracks this metric — controls whether Trends can
    /// draw a baseline band behind the line. Strain/sleep-performance/readiness
    /// aren't baselined (design doc lists HRV/RHR/respiratory rate/skin
    /// temp/SpO2 specifically), so those charts show the raw line only.
    var hasBaseline: Bool { BaselineEngine.metrics.contains(columnName) }

    /// Reverse lookup from a SQL column name (as stored in `anomalies.metric`)
    /// back to the case that knows how to display it — the one place this
    /// mapping lives, so a display label never has to be reconstructed by
    /// string-munging a snake_case column name.
    init?(columnName: String) {
        guard let match = Self.allCases.first(where: { $0.columnName == columnName }) else { return nil }
        self = match
    }
}

struct CorrelationRow: Decodable, FetchableRecord, Identifiable {
    var id: String { predictor }
    var predictor: String
    var outcome: String
    var lagDays: Int
    var rho: Double
    var n: Int
    var pValueBhCorrected: Double?
    var strength: String?

    enum CodingKeys: String, CodingKey {
        case predictor, outcome, rho, n, strength
        case lagDays = "lag_days"
        case pValueBhCorrected = "p_value_bh_corrected"
    }

    var strengthEnum: Stats.Strength { strength.flatMap(Stats.Strength.init) ?? .insufficient }
}

struct AnomalyRow: Decodable, FetchableRecord, Identifiable {
    var id: Int64
    var day: String
    var kind: String
    var metric: String?
    var zScore: Double?
    var detailJson: String?

    enum CodingKeys: String, CodingKey {
        case id, day, kind, metric
        case zScore = "z_score"
        case detailJson = "detail_json"
    }

    /// The signals behind an illness flag. Empty when the detail can't be
    /// read: the flag still stands, it just can't name its signals.
    var illnessSignals: [Metric] {
        guard let data = detailJson?.data(using: .utf8),
              let detail = try? JSONDecoder().decode(AnomalyEngine.IllnessDetail.self, from: data) else { return [] }
        return detail.triggeredSignals.compactMap(Metric.init(column:))
    }
}

struct LatestSleepDetail: Decodable, FetchableRecord {
    var start: Int64
    var end: Int64
    var lightMs: Int64?
    var swsMs: Int64?
    var remMs: Int64?
    var awakeMs: Int64?
    var performancePercentage: Double?

    enum CodingKeys: String, CodingKey {
        case start, end
        case lightMs = "total_light_sleep_time_milli"
        case swsMs = "total_slow_wave_sleep_time_milli"
        case remMs = "total_rem_sleep_time_milli"
        case awakeMs = "total_awake_time_milli"
        case performancePercentage = "sleep_performance_percentage"
    }

    var interval: Range<Date> {
        Date(timeIntervalSince1970: TimeInterval(start))..<Date(timeIntervalSince1970: TimeInterval(end))
    }

    /// Ended today or yesterday, so "last night" is true of it.
    func isFromLastNight(calendar: Calendar = .current, now: Date = .now) -> Bool {
        let end = interval.upperBound
        return calendar.isDate(end, inSameDayAs: now)
            || calendar.date(byAdding: .day, value: -1, to: now).map { calendar.isDate(end, inSameDayAs: $0) } == true
    }

    /// Light + deep + REM. `nil` when WHOOP sent no stage totals.
    var asleepMilli: Int64? {
        guard lightMs != nil || swsMs != nil || remMs != nil else { return nil }
        return (lightMs ?? 0) + (swsMs ?? 0) + (remMs ?? 0)
    }
}

enum AnalysisQueries {
    static func latestDailyMetrics(_ db: GRDB.Database) throws -> DailyMetricsRow? {
        try DailyMetricsRow.fetchOne(db, sql: "SELECT * FROM daily_metrics ORDER BY day DESC LIMIT 1")
    }

    static func dailyMetrics(_ db: GRDB.Database, sinceDay: String?) throws -> [DailyMetricsRow] {
        if let sinceDay {
            return try DailyMetricsRow.fetchAll(db, sql: "SELECT * FROM daily_metrics WHERE day >= ? ORDER BY day ASC", arguments: [sinceDay])
        }
        return try DailyMetricsRow.fetchAll(db, sql: "SELECT * FROM daily_metrics ORDER BY day ASC")
    }

    /// Baseline mean/stddev per day for one metric+window — the shaded band
    /// behind a Trends line chart. Keyed by day so the chart can look up a
    /// point's band without a second round-trip per point.
    static func baselineBand(_ db: GRDB.Database, metric: String, sinceDay: String?, window: Int = 60) throws -> [String: (mean: Double, stddev: Double)] {
        let rows: [Row]
        if let sinceDay {
            rows = try Row.fetchAll(
                db, sql: "SELECT day, mean_val, stddev_val FROM baselines WHERE metric = ? AND window_days = ? AND day >= ?",
                arguments: [metric, window, sinceDay]
            )
        } else {
            rows = try Row.fetchAll(
                db, sql: "SELECT day, mean_val, stddev_val FROM baselines WHERE metric = ? AND window_days = ?",
                arguments: [metric, window]
            )
        }
        var result: [String: (mean: Double, stddev: Double)] = [:]
        for row in rows {
            guard let mean = row["mean_val"] as Double?, let stddev = row["stddev_val"] as Double? else { continue }
            result[row["day"]] = (mean, stddev)
        }
        return result
    }

    /// Each day's normal range for one metric, keyed by day.
    static func normalRanges(_ db: GRDB.Database, metric: Metric, sinceDay: String?) throws -> [String: NormalRange] {
        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT day, mean_val, stddev_val FROM baselines
            WHERE metric = ? AND window_days = ? AND (? IS NULL OR day >= ?)
            """,
            arguments: [metric.column, NormalRange.windowDays, sinceDay, sinceDay]
        )
        return Dictionary(uniqueKeysWithValues: rows.compactMap { row -> (String, NormalRange)? in
            guard let mean = row["mean_val"] as Double?, let stddev = row["stddev_val"] as Double? else { return nil }
            return (row["day"], NormalRange(mean: mean, standardDeviation: stddev))
        })
    }

    /// Every metric's normal range on one day.
    static func normalRanges(_ db: GRDB.Database, day: String) throws -> [Metric: NormalRange] {
        let rows = try Row.fetchAll(
            db,
            sql: "SELECT metric, mean_val, stddev_val FROM baselines WHERE day = ? AND window_days = ?",
            arguments: [day, NormalRange.windowDays]
        )
        return Dictionary(uniqueKeysWithValues: rows.compactMap { row -> (Metric, NormalRange)? in
            guard let metric = Metric(column: row["metric"]),
                  let mean = row["mean_val"] as Double?, let stddev = row["stddev_val"] as Double? else { return nil }
            return (metric, NormalRange(mean: mean, standardDeviation: stddev))
        })
    }

    /// Ranked for Insights: real findings (n >= 30, sorted by |rho| descending)
    /// first, then everything still building toward significance — grouping
    /// them this way in SQL means the view never has to know the ordering rule.
    static func correlations(_ db: GRDB.Database) throws -> [CorrelationRow] {
        try CorrelationRow.fetchAll(
            db, sql: """
            SELECT * FROM correlations
            ORDER BY (strength != 'insufficient') DESC, ABS(rho) DESC
            """
        )
    }

    static func anomalies(_ db: GRDB.Database, sinceDay: String?, limit: Int = 90) throws -> [AnomalyRow] {
        if let sinceDay {
            return try AnomalyRow.fetchAll(
                db, sql: "SELECT * FROM anomalies WHERE day >= ? ORDER BY day DESC LIMIT ?",
                arguments: [sinceDay, limit]
            )
        }
        return try AnomalyRow.fetchAll(db, sql: "SELECT * FROM anomalies ORDER BY day DESC LIMIT ?", arguments: [limit])
    }

    static func anomalies(_ db: GRDB.Database, day: String) throws -> [AnomalyRow] {
        try AnomalyRow.fetchAll(db, sql: "SELECT * FROM anomalies WHERE day = ?", arguments: [day])
    }

    static func latestSleepDetail(_ db: GRDB.Database) throws -> LatestSleepDetail? {
        try LatestSleepDetail.fetchOne(
            db, sql: """
            SELECT s.start, s.end, s.sleep_performance_percentage,
                   st.total_light_sleep_time_milli, st.total_slow_wave_sleep_time_milli,
                   st.total_rem_sleep_time_milli, st.total_awake_time_milli
            FROM sleeps s LEFT JOIN sleep_stage_summary st ON st.sleep_id = s.id
            WHERE s.nap = 0
            ORDER BY s.start DESC LIMIT 1
            """
        )
    }

    static func lastSyncedAt(_ db: GRDB.Database) throws -> Date? {
        guard let seconds = try Int64.fetchOne(db, sql: "SELECT MAX(finished_at) FROM sync_log WHERE finished_at IS NOT NULL") else {
            return nil
        }
        return Date(timeIntervalSince1970: Double(seconds))
    }

    static func lastSyncError(_ db: GRDB.Database) throws -> String? {
        try String.fetchOne(db, sql: "SELECT error FROM sync_log WHERE error IS NOT NULL ORDER BY id DESC LIMIT 1")
    }
}
