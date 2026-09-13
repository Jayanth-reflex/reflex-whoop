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

    private func insertAnomaly(day: String, kind: AnomalyEngine.Kind, metric: String?) throws {
        try database.dbPool.write { db in
            try db.execute(
                sql: "INSERT INTO anomalies (day, kind, metric, z_score, algo_version, computed_at) VALUES (?, ?, ?, 2.5, 1, 0)",
                arguments: [day, kind.rawValue, metric]
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
        XCTAssertTrue(today.hasIllnessFlag)
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
        XCTAssertFalse(days[0].isPossibleIllness)
        XCTAssertTrue(days[1].isPossibleIllness)
        XCTAssertTrue(days[1].readings.isEmpty)
    }
}
