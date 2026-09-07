import XCTest
import GRDB
@testable import ReflexWhoop

/// The two tests the design doc calls out by name for the analysis engine:
/// a planted correlation must be recovered within tolerance, and a pure-noise
/// dataset must produce no surviving finding once Benjamini-Hochberg correction
/// is applied across the whole predictor batch.
final class CorrelationEngineTests: XCTestCase {
    private let dayCount = 200
    private let startDay = "2024-01-01"

    func testPlantedCorrelationIsRecoveredWithinTolerance() throws {
        let db = try TestSupport.makeDatabase()
        var rng = SeededGenerator(seed: 1)

        try db.dbPool.write { conn in
            // Pass 1: every day gets a strain value and an empty recovery slot.
            for i in 0..<self.dayCount {
                let strain = 8 + 6 * Double.random(in: 0...1, using: &rng) // 8...14
                try Self.insertDailyMetric(conn, day: self.day(offset: i), dayStrain: strain, recoveryScore: nil)
            }

            // Pass 2: plant the relationship — each day's recovery is a linear
            // (noisy) function of the *previous* day's strain, which is exactly
            // what CorrelationEngine's "day i predicts day i+1" lag should find.
            for i in 1..<self.dayCount {
                let priorStrain = try Double.fetchOne(conn, sql: "SELECT day_strain FROM daily_metrics WHERE day = ?", arguments: [self.day(offset: i - 1)])!
                let noise = (Double.random(in: 0...1, using: &rng) - 0.5) * 6
                let recovery = min(max(85 - 3.5 * priorStrain + noise, 5), 100)
                try Self.updateRecovery(conn, day: self.day(offset: i), recoveryScore: recovery)
            }

            try CorrelationEngine.recomputeAll(conn)
        }

        let rows = try db.dbPool.read { conn in try CorrelationRow.fetchAll(conn, sql: "SELECT * FROM correlations WHERE predictor = 'prior_day_strain'") }
        let planted = try XCTUnwrap(rows.first, "prior_day_strain should have enough paired data to produce a correlation")

        XCTAssertLessThan(planted.rho, -0.5, "a strong planted negative relationship should be recovered as a strongly negative rho")
        XCTAssertGreaterThanOrEqual(planted.n, 30)
        XCTAssertEqual(planted.strengthEnum, .strong)
        XCTAssertLessThan(planted.pValueBhCorrected ?? 1, 0.01, "a real, strong relationship must survive multiple-testing correction")
    }

    func testPureNoiseProducesNoSurvivingFindingAfterCorrection() throws {
        let db = try TestSupport.makeDatabase()
        var rng = SeededGenerator(seed: 2)

        try db.dbPool.write { conn in
            for i in 0..<self.dayCount {
                let day = self.day(offset: i)
                // Every predictor and the outcome are independently drawn —
                // by construction, nothing here is related to anything else.
                try Self.insertDailyMetric(
                    conn, day: day,
                    dayStrain: 8 + 6 * Double.random(in: 0...1, using: &rng),
                    recoveryScore: 40 + 40 * Double.random(in: 0...1, using: &rng)
                )
                try Self.insertSyntheticSleep(conn, day: day, rng: &rng)
            }
            try CorrelationEngine.recomputeAll(conn)
        }

        let rows = try db.dbPool.read { conn in try CorrelationRow.fetchAll(conn, sql: "SELECT * FROM correlations") }
        XCTAssertFalse(rows.isEmpty, "the noise dataset should still be large enough to produce testable predictor pairs")

        for row in rows {
            XCTAssertGreaterThanOrEqual(
                row.pValueBhCorrected ?? 1, 0.05,
                "'\(row.predictor)' looked significant on pure noise — Benjamini-Hochberg correction failed to catch a false positive"
            )
        }
    }

    // MARK: - Fixture helpers

    private func day(offset: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let base = formatter.date(from: startDay)!
        return formatter.string(from: base.addingTimeInterval(Double(offset) * 86400))
    }

    private static func insertDailyMetric(_ db: GRDB.Database, day: String, dayStrain: Double?, recoveryScore: Double?) throws {
        try db.execute(
            sql: """
            INSERT INTO daily_metrics (day, day_strain, recovery_score, algo_version, computed_at)
            VALUES (?, ?, ?, 1, 0)
            ON CONFLICT(day) DO UPDATE SET day_strain = excluded.day_strain
            """,
            arguments: [day, dayStrain, recoveryScore]
        )
    }

    private static func updateRecovery(_ db: GRDB.Database, day: String, recoveryScore: Double?) throws {
        try db.execute(sql: "UPDATE daily_metrics SET recovery_score = ? WHERE day = ?", arguments: [recoveryScore, day])
    }

    private static func insertSyntheticSleep(_ db: GRDB.Database, day: String, rng: inout SeededGenerator) throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let dayStart = Int64(formatter.date(from: day)!.timeIntervalSince1970)
        let sleepID = "sleep-\(day)"
        let durationSeconds: Int64 = 6 * 3600 + Int64(Double.random(in: 0...1, using: &rng) * 3600 * 3)

        try db.execute(
            sql: """
            INSERT INTO sleeps (id, start, end, nap, score_state, sleep_efficiency_percentage, sleep_consistency_percentage, source)
            VALUES (?, ?, ?, 0, 'SCORED', ?, ?, 'api')
            """,
            arguments: [
                sleepID, dayStart, dayStart + durationSeconds,
                70 + 25 * Double.random(in: 0...1, using: &rng),
                50 + 40 * Double.random(in: 0...1, using: &rng),
            ]
        )

        let remMs = Double.random(in: 0...1, using: &rng) * 5_400_000
        let swsMs = Double.random(in: 0...1, using: &rng) * 5_400_000
        let lightMs = Double.random(in: 0...1, using: &rng) * 10_800_000
        try db.execute(
            sql: """
            INSERT INTO sleep_stage_summary
                (sleep_id, total_rem_sleep_time_milli, total_slow_wave_sleep_time_milli, total_light_sleep_time_milli, disturbance_count)
            VALUES (?, ?, ?, ?, ?)
            """,
            arguments: [sleepID, remMs, swsMs, lightMs, Int(Double.random(in: 0...1, using: &rng) * 10)]
        )
    }
}
