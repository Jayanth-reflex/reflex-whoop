import XCTest
import GRDB
@testable import ReflexWhoop

final class ReadModelTests: XCTestCase {
    private var database: ReflexWhoop.Database!

    override func setUpWithError() throws {
        database = try TestSupport.makeDatabase()
    }

    private func insertDay(_ day: String, recovery: Double? = nil, hrv: Double? = nil) throws {
        try database.dbPool.write { db in
            try db.execute(
                sql: """
                INSERT INTO daily_metrics (day, recovery_score, hrv_rmssd_milli, algo_version, computed_at)
                VALUES (?, ?, ?, 1, 0)
                """,
                arguments: [day, recovery, hrv]
            )
        }
    }

    private func insertBaseline(_ metric: String, day: String, mean: Double, stddev: Double, window: Int = NormalRange.windowDays) throws {
        try database.dbPool.write { db in
            try db.execute(
                sql: """
                INSERT INTO baselines (metric, day, window_days, mean_val, stddev_val, z_score, algo_version, computed_at)
                VALUES (?, ?, ?, ?, ?, NULL, 1, 0)
                """,
                arguments: [metric, day, window, mean, stddev]
            )
        }
    }

    private func insertAnomaly(day: String, kind: AnomalyEngine.Kind, metric: String?, detail: String? = nil) throws {
        try database.dbPool.write { db in
            try db.execute(
                sql: "INSERT INTO anomalies (day, kind, metric, z_score, detail_json, algo_version, computed_at) VALUES (?, ?, ?, 2.5, ?, 1, 0)",
                arguments: [day, kind.rawValue, metric, detail]
            )
        }
    }

    func testTodayIsNilWithNoDays() throws {
        XCTAssertNil(try database.dbPool.read(TodaySnapshot.load))
    }

    func testTodayUsesLatestDayAndOnlyTheNormalRangeWindow() throws {
        try insertDay("2026-09-11", recovery: 40, hrv: 50)
        try insertDay("2026-09-12", recovery: 85, hrv: 74)
        try insertBaseline("hrv_rmssd_milli", day: "2026-09-12", mean: 64, stddev: 6)
        try insertBaseline("hrv_rmssd_milli", day: "2026-09-12", mean: 99, stddev: 1, window: 30)
        try insertAnomaly(day: "2026-09-12", kind: .illnessFlag, metric: nil)

        let today = try XCTUnwrap(try database.dbPool.read(TodaySnapshot.load))
        XCTAssertEqual(today.metrics.day, "2026-09-12")
        XCTAssertEqual(today.ranges[.heartRateVariability], NormalRange(mean: 64, standardDeviation: 6))
        XCTAssertEqual(today.status(of: .heartRateVariability), .above)
        XCTAssertEqual(today.status(of: .bloodOxygen), .noReading)
        XCTAssertEqual(today.status(of: .recovery), .notEnoughHistory)
        XCTAssertNotNil(today.illnessFlag)
    }

    func testIllnessSignalsAreReadFromTheFlagInTheEnginesOrder() throws {
        try insertDay("2026-09-12", recovery: 20)
        try insertAnomaly(
            day: "2026-09-12",
            kind: .illnessFlag,
            metric: nil,
            detail: #"{"triggeredSignals":["respiratory_rate","resting_heart_rate","hrv_rmssd_milli"],"zScores":{}}"#
        )
        let today = try XCTUnwrap(try database.dbPool.read(TodaySnapshot.load))
        XCTAssertEqual(today.illnessFlag?.illnessSignals, [.breathingRate, .restingHeartRate, .heartRateVariability])
    }

    /// A flag whose detail can't be read is still a flag; it just can't name its signals.
    func testUnreadableIllnessDetailStillFlagsTheDay() throws {
        try insertDay("2026-09-12", recovery: 20)
        try insertAnomaly(day: "2026-09-12", kind: .illnessFlag, metric: nil, detail: "not json")
        let today = try XCTUnwrap(try database.dbPool.read(TodaySnapshot.load))
        XCTAssertEqual(today.illnessFlag?.illnessSignals, [])
    }

    func testTodayWithoutAFlagHasNone() throws {
        try insertDay("2026-09-12", recovery: 80)
        XCTAssertNil(try XCTUnwrap(try database.dbPool.read(TodaySnapshot.load)).illnessFlag)
    }

    func testHistorySummary() throws {
        let summary = try XCTUnwrap(MetricHistorySummary(values: [60, 74, 50]))
        XCTAssertEqual(summary.average, 61.333, accuracy: 0.001)
        XCTAssertEqual(summary.lowest, 50)
        XCTAssertEqual(summary.highest, 74)
        XCTAssertEqual(summary.count, 3)
        XCTAssertNil(MetricHistorySummary(values: []))
    }

    func testHistorySkipsMissingValuesAndAttachesPerDayRanges() throws {
        try insertDay("2026-09-10", hrv: 60)
        try insertDay("2026-09-11")
        try insertDay("2026-09-12", hrv: 74)
        try insertBaseline("hrv_rmssd_milli", day: "2026-09-12", mean: 64, stddev: 6)

        let points = try database.dbPool.read { try MetricHistory.points($0, metric: .heartRateVariability, sinceDay: "2026-09-10") }
        XCTAssertEqual(points.map(\.day), ["2026-09-10", "2026-09-12"])
        XCTAssertNil(points[0].range)
        XCTAssertEqual(points[1].status, .above)
    }

    func testHistoryRespectsTheFirstDay() throws {
        try insertDay("2026-09-10", hrv: 60)
        try insertDay("2026-09-12", hrv: 74)
        let points = try database.dbPool.read { try MetricHistory.points($0, metric: .heartRateVariability, sinceDay: "2026-09-11") }
        XCTAssertEqual(points.map(\.day), ["2026-09-12"])
    }

    func testUnusualDaysGroupByDayWithValuesAndRanges() throws {
        try insertDay("2026-09-09", hrv: 52)
        try insertBaseline("hrv_rmssd_milli", day: "2026-09-09", mean: 64, stddev: 5)
        try insertAnomaly(day: "2026-09-09", kind: .singleMetricExcursion, metric: "hrv_rmssd_milli")
        try insertAnomaly(day: "2026-08-30", kind: .illnessFlag, metric: nil)

        let days = try database.dbPool.read { try UnusualDays.load($0, sinceDay: nil) }
        XCTAssertEqual(days.map(\.day), ["2026-09-09", "2026-08-30"])
        XCTAssertEqual(days[0].readings.map(\.metric), [.heartRateVariability])
        XCTAssertEqual(days[0].readings[0].status, .unusuallyLow)
        XCTAssertNil(days[0].illnessSignals)
        XCTAssertNotNil(days[1].illnessSignals)
        XCTAssertTrue(days[1].readings.isEmpty)
    }

    func testSleepIsFromLastNightOnlyWhenItEndedTodayOrYesterday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Kolkata"))
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-13T12:00:00+05:30"))
        func sleep(endingAt iso: String) throws -> LatestSleepDetail {
            let end = try XCTUnwrap(ISO8601DateFormatter().date(from: iso))
            return LatestSleepDetail(start: Int64(end.timeIntervalSince1970) - 28_800, end: Int64(end.timeIntervalSince1970))
        }
        XCTAssertTrue(try sleep(endingAt: "2026-09-13T06:40:00+05:30").isFromLastNight(calendar: calendar, now: now))
        XCTAssertTrue(try sleep(endingAt: "2026-09-12T07:00:00+05:30").isFromLastNight(calendar: calendar, now: now))
        XCTAssertFalse(try sleep(endingAt: "2026-09-11T07:00:00+05:30").isFromLastNight(calendar: calendar, now: now))
    }

    func testHistoryForSeveralMetricsMatchesOneAtATime() throws {
        try insertDay("2026-09-10", recovery: 40, hrv: 60)
        try insertDay("2026-09-12", recovery: 85)
        try insertBaseline("hrv_rmssd_milli", day: "2026-09-10", mean: 64, stddev: 6)

        let together = try database.dbPool.read { try MetricHistory.points($0, metrics: [.recovery, .heartRateVariability], sinceDay: nil) }
        for metric in [Metric.recovery, .heartRateVariability] {
            let alone = try database.dbPool.read { try MetricHistory.points($0, metric: metric, sinceDay: nil) }
            XCTAssertEqual(together[metric], alone)
        }
    }

    /// "All" history must list every unusual day, not the most recent few.
    func testUnusualDaysAreNotCapped() throws {
        for offset in 0..<120 {
            let day = RecordDAO.dayString(for: Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86_400))
            try insertAnomaly(day: day, kind: .illnessFlag, metric: nil)
        }
        XCTAssertEqual(try database.dbPool.read { try UnusualDays.load($0, sinceDay: nil) }.count, 120)
    }

    /// Trends shows the count without building each day.
    func testUnusualDayCountMatchesTheListInEveryRange() throws {
        try insertAnomaly(day: "2026-09-09", kind: .singleMetricExcursion, metric: "hrv_rmssd_milli")
        try insertAnomaly(day: "2026-09-09", kind: .illnessFlag, metric: nil)
        try insertAnomaly(day: "2026-08-30", kind: .illnessFlag, metric: nil)

        for sinceDay in [nil, "2026-09-01", "2026-09-10"] {
            let (count, days) = try database.dbPool.read { db in
                (try UnusualDays.count(db, sinceDay: sinceDay), try UnusualDays.load(db, sinceDay: sinceDay))
            }
            XCTAssertEqual(count, days.count, "since \(sinceDay ?? "the start")")
        }
    }

    func testUnusualDaysCarryTheIllnessSignals() throws {
        try insertAnomaly(
            day: "2026-08-30",
            kind: .illnessFlag,
            metric: nil,
            detail: #"{"triggeredSignals":["respiratory_rate","skin_temp_celsius","resting_heart_rate"],"zScores":{}}"#
        )
        let day = try XCTUnwrap(try database.dbPool.read { try UnusualDays.load($0, sinceDay: nil) }.first)
        XCTAssertEqual(day.illnessSignals, [.breathingRate, .skinTemperature, .restingHeartRate])
    }

    /// Readiness is hidden until its sleep-debt input is rebuilt, so no read
    /// model may carry it, even when the column has a value.
    func testReadinessReachesNoReadModel() throws {
        try insertDay("2026-09-12", recovery: 80)
        try database.dbPool.write { try $0.execute(sql: "UPDATE daily_metrics SET readiness_score = 77, sleep_debt_milli = 7668000") }
        let today = try XCTUnwrap(try database.dbPool.read(TodaySnapshot.load))
        let fields = Mirror(reflecting: today.metrics).children.compactMap(\.label)
        XCTAssertFalse(fields.contains { $0.localizedStandardContains("readiness") || $0.localizedStandardContains("debt") })
        XCTAssertFalse(Metric.allCases.contains { $0.column == "readiness_score" })
    }
}
