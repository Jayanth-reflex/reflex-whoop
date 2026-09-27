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

    /// v4 changes only indexes. The archive is the one thing here that can't be rebuilt,
    /// so an upgrade over real rows must leave every one of them byte-for-byte the same.
    func testUpgradingAPopulatedDatabaseKeepsEveryInboxRow() throws {
        let path = NSTemporaryDirectory() + "reflexwhoop-test-\(UUID().uuidString).sqlite"
        let pool = try DatabasePool(path: path)
        try Migrator.makeMigrator().migrate(pool, upTo: "v3_session_metrics_and_source_state")
        try pool.write { db in
            for i in 0..<200 {
                let seq = try IngestInbox.append(db, source: i % 10 == 0 ? .api : .ble, kind: "FD4B0005",
                                                 payload: Data([UInt8(i % 256), 0x7E]),
                                                 receivedAt: Date(timeIntervalSince1970: TimeInterval(1_000 + i)))
                if i % 3 == 0 { try IngestInbox.markDecoded(db, seq: seq, decoderVersion: 1) }
            }
        }
        let snapshot = "SELECT seq, source, kind, received_at, hex(payload), codec, decoded_at, decoder_version FROM ingest_inbox ORDER BY seq"
        let before = try pool.read { try Row.fetchAll($0, sql: snapshot) }

        try Migrator.makeMigrator().migrate(pool)

        let after = try pool.read { try Row.fetchAll($0, sql: snapshot) }
        XCTAssertEqual(after, before)
        XCTAssertEqual(after.count, 200)
    }

    /// SQLite applies `auto_vacuum` to an existing file only during a full VACUUM, so the
    /// pragma the app set on every launch never took on the phone: its file reported
    /// `auto_vacuum = 0` and could only grow. `compact()` does the one full VACUUM that
    /// switches it over, then returns free pages from then on.
    func testCompactSwitchesAnOldFileToIncrementalVacuumAndReclaimsFreePages() async throws {
        let path = NSTemporaryDirectory() + "reflexwhoop-test-\(UUID().uuidString).sqlite"
        // A file made the way the phone's was: tables first, so auto_vacuum stays NONE.
        do {
            let queue = try DatabaseQueue(path: path)
            try await queue.write { db in
                try db.execute(sql: "CREATE TABLE scratch (blob BLOB)")
                for _ in 0..<400 { try db.execute(sql: "INSERT INTO scratch VALUES (randomblob(4000))") }
                try db.execute(sql: "DELETE FROM scratch")
            }
        }
        let db = try ReflexWhoop.Database(path: path)
        func pragma(_ name: String) async throws -> Int {
            try await db.dbPool.read { try Int.fetchOne($0, sql: "PRAGMA \(name)") ?? -1 }
        }
        let modeBefore = try await pragma("auto_vacuum")
        let freeBefore = try await pragma("freelist_count")
        XCTAssertEqual(modeBefore, 0, "precondition: opening the app never switched it")
        XCTAssertGreaterThan(freeBefore, 0)

        try await db.compact()

        let modeAfter = try await pragma("auto_vacuum")
        let freeAfter = try await pragma("freelist_count")
        XCTAssertEqual(modeAfter, 2, "INCREMENTAL")
        XCTAssertEqual(freeAfter, 0)
        let walBytes = (try? FileManager.default.attributesOfItem(atPath: path + "-wal")[.size] as? NSNumber)?.intValue ?? 0
        XCTAssertLessThan(walBytes, 64 * 1024, "VACUUM writes the whole file through the WAL; it must be truncated after")

        // It runs unattended in a background task, so it has to leave proof that it did.
        let compactedAt = try await db.dbPool.read { try String.fetchOne($0, sql: "SELECT value FROM schema_meta WHERE key = 'compacted_at'") }
        XCTAssertNotNil(compactedAt)
    }

    func testOnDiskByteCountCoversTheStore() throws {
        let db = try TestSupport.makeDatabase()
        let mainFileSize = try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: db.path)[.size] as? NSNumber).int64Value
        XCTAssertGreaterThanOrEqual(db.onDiskByteCount(), mainFileSize)
        XCTAssertGreaterThan(mainFileSize, 0)
    }
}
