import XCTest
import GRDB
@testable import ReflexWhoop

final class SourceStatusTests: XCTestCase {
    private var database: ReflexWhoop.Database!

    override func setUpWithError() throws {
        database = try TestSupport.makeDatabase()
    }

    private func insertSyncLog(error: String?, errorKind: SyncErrorKind?) throws {
        try database.dbPool.write { db in
            try db.execute(
                sql: """
                INSERT INTO sync_log (started_at, finished_at, trigger, requests_made, records_upserted, error, error_kind)
                VALUES (100, 200, 'test', 1, 0, ?, ?)
                """,
                arguments: [error, errorKind?.rawValue]
            )
        }
    }

    func testNoCredentialsIsNotConfigured() throws {
        try database.dbPool.read { db in
            let state = try SourceStatus.whoop(db, isSignedIn: false, hasCredentials: false)
            XCTAssertEqual(state, .notConfigured)
            XCTAssertFalse(state.canCollect)
        }
    }

    func testCredentialsButSignedOutIsUnauthorized() throws {
        try database.dbPool.read { db in
            XCTAssertEqual(try SourceStatus.whoop(db, isSignedIn: false, hasCredentials: true), .unauthorized)
        }
    }

    func testSuccessfulSyncIsActive() throws {
        try insertSyncLog(error: nil, errorKind: nil)
        try database.dbPool.read { db in
            let state = try SourceStatus.whoop(db, isSignedIn: true, hasCredentials: true)
            XCTAssertEqual(state, .active(lastSuccess: Date(timeIntervalSince1970: 200)))
            XCTAssertTrue(state.canCollect)
        }
    }

    /// The distinction the whole archive-mode design rests on: a lapsed
    /// membership must not read as a transient network blip, because the app's
    /// response to each is different.
    func testForbiddenIsInactiveNotUnreachable() throws {
        try insertSyncLog(error: "WHOOP denied access", errorKind: .forbidden)
        try database.dbPool.read { db in
            let state = try SourceStatus.whoop(db, isSignedIn: true, hasCredentials: true)
            guard case .inactive = state else {
                return XCTFail("403 must classify as inactive, got \(state)")
            }
            XCTAssertFalse(state.canCollect)
        }
    }

    func testTransientErrorIsUnreachableAndStillCollectable() throws {
        try insertSyncLog(error: "The network connection was lost", errorKind: .transport)
        try database.dbPool.read { db in
            let state = try SourceStatus.whoop(db, isSignedIn: true, hasCredentials: true)
            guard case .unreachable = state else {
                return XCTFail("a transport error must classify as unreachable, got \(state)")
            }
            XCTAssertTrue(state.canCollect, "a dropped connection is retryable, unlike a lapsed membership")
        }
    }

    func testClassifyMapsForbiddenClientError() {
        XCTAssertEqual(SyncErrorKind.classify(WhoopClient.ClientError.forbidden(body: "")), .forbidden)
        XCTAssertEqual(SyncErrorKind.classify(WhoopClient.ClientError.http(status: 401, body: "")), .unauthorized)
        XCTAssertEqual(SyncErrorKind.classify(WhoopClient.ClientError.http(status: 500, body: "")), .other)
        XCTAssertEqual(SyncErrorKind.classify(URLError(.notConnectedToInternet)), .transport)
    }

    func testArchiveSummaryReportsSpanIndependentOfSources() throws {
        try database.dbPool.write { db in
            for day in ["2026-01-01", "2026-01-02", "2026-01-03"] {
                try db.execute(
                    sql: "INSERT INTO daily_metrics (day, algo_version, computed_at) VALUES (?, 1, 0)",
                    arguments: [day]
                )
            }
        }
        try database.dbPool.read { db in
            let archive = try SourceStatus.archive(db)
            XCTAssertEqual(archive.dayCount, 3)
            XCTAssertEqual(archive.firstDate, DayDates.keyDate("2026-01-01", calendar: .current))
            XCTAssertEqual(archive.lastDate, DayDates.keyDate("2026-01-03", calendar: .current))
            XCTAssertFalse(archive.isEmpty)
        }
    }

    func testEmptyArchiveIsReportedAsEmpty() throws {
        try database.dbPool.read { db in
            XCTAssertTrue(try SourceStatus.archive(db).isEmpty)
        }
    }

    func testSchemaMetaIsStamped() throws {
        try database.dbPool.read { db in
            let version = try String.fetchOne(db, sql: "SELECT value FROM schema_meta WHERE key = 'schema_version'")
            XCTAssertEqual(version, Migrator.latestMigrationName)
            XCTAssertNotNil(try String.fetchOne(db, sql: "SELECT value FROM schema_meta WHERE key = 'ble_decoder_version'"))
        }
    }
}
