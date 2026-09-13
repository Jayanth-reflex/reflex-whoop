import XCTest
import GRDB
@testable import ReflexWhoop

final class DatabaseTests: XCTestCase {
    func testFreshDatabaseCreatesAllLayerTables() throws {
        let db = try TestSupport.makeDatabase()
        let expectedTables = [
            "ingest_inbox",
            "cycles", "recoveries", "sleeps", "sleep_stage_summary", "sleep_need",
            "workouts", "workout_zone_durations", "body_measurements", "profile",
            "ble_sessions", "ts_chunk", "ts_rollup_minute",
            "daily_metrics", "baselines", "correlations", "anomalies", "session_metrics",
            "sync_state", "pending_scores", "sync_log", "dirty_days", "schema_meta",
        ]

        try db.dbPool.read { conn in
            for table in expectedTables {
                XCTAssertTrue(try conn.tableExists(table), "missing table: \(table)")
            }
        }
    }

    func testReopeningSamePathIsIdempotent() throws {
        let path = NSTemporaryDirectory() + "reflexwhoop-test-\(UUID().uuidString).sqlite"
        _ = try ReflexWhoop.Database(path: path)
        // Second open runs the migrator again against an already-migrated file.
        // Must not throw or duplicate schema objects.
        XCTAssertNoThrow(try ReflexWhoop.Database(path: path))
    }

    func testForeignKeysAreEnforced() throws {
        let db = try TestSupport.makeDatabase()
        try db.dbPool.write { conn in
            // sleep_stage_summary.sleep_id references sleeps(id); inserting without
            // a matching parent row must fail now that foreign keys are enabled.
            XCTAssertThrowsError(
                try conn.execute(
                    sql: "INSERT INTO sleep_stage_summary (sleep_id) VALUES ('does-not-exist')"
                )
            )
        }
    }

    func testRunMaintenanceDoesNotThrow() async throws {
        let db = try TestSupport.makeDatabase()
        try await db.runMaintenance()
    }

    func testOnDiskByteCountCoversTheStore() throws {
        let db = try TestSupport.makeDatabase()
        let mainFileSize = try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: db.path)[.size] as? NSNumber).int64Value
        XCTAssertGreaterThanOrEqual(db.onDiskByteCount(), mainFileSize)
        XCTAssertGreaterThan(mainFileSize, 0)
    }
}
