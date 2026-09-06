import XCTest
import GRDB
@testable import ReflexWhoop

/// End-to-end: inbox append -> normalizer drain -> normalized tables. This is the
/// path a real sync actually exercises; RecordDAOTests covers the upsert logic in
/// isolation, this covers the wiring between inbox, decode dispatch, and DAO calls.
final class ApiNormalizerTests: XCTestCase {
    func testCyclePageDecodesBothScoredAndPendingRecords() throws {
        let db = try TestSupport.makeDatabase()
        let payload = try TestSupport.loadFixture("cycle_page")

        try db.dbPool.write { conn in
            try IngestInbox.append(conn, source: .api, kind: ApiNormalizer.Kind.cyclePage, payload: payload)
        }

        let stats = try ApiNormalizer.processPending(db.dbPool)
        XCTAssertEqual(stats.processed, 1)
        XCTAssertEqual(stats.upserted, 1)
        XCTAssertEqual(stats.failed, 0)

        try db.dbPool.read { conn in
            let count = try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM cycles") ?? 0
            XCTAssertEqual(count, 2)

            let strain = try Double.fetchOne(conn, sql: "SELECT strain FROM cycles WHERE id = '93845'")
            XCTAssertEqual(strain ?? -1, 5.2951527, accuracy: 0.0001)

            let pendingCount = try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM pending_scores WHERE resource = 'cycle'") ?? 0
            XCTAssertEqual(pendingCount, 1, "the PENDING_SCORE record should be tracked for re-fetch")
        }

        // The inbox row must be marked decoded so it's never reprocessed.
        try db.dbPool.read { conn in
            let undecoded = try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM ingest_inbox WHERE decoded_at IS NULL") ?? 0
            XCTAssertEqual(undecoded, 0)
        }
    }

    func testRecoveryPageDecodesCorrectly() throws {
        let db = try TestSupport.makeDatabase()
        let payload = try TestSupport.loadFixture("recovery_page")
        try db.dbPool.write { conn in
            try IngestInbox.append(conn, source: .api, kind: ApiNormalizer.Kind.recoveryPage, payload: payload)
        }
        _ = try ApiNormalizer.processPending(db.dbPool)

        try db.dbPool.read { conn in
            let hrv = try Double.fetchOne(conn, sql: "SELECT hrv_rmssd_milli FROM recoveries WHERE cycle_id = '93845'")
            XCTAssertEqual(hrv ?? -1, 31.813562, accuracy: 0.0001)
        }
    }

    func testBodyMeasurementDefersUntilProfileExistsThenSelfHealsOnNextPass() throws {
        let db = try TestSupport.makeDatabase()
        let bodyPayload = try TestSupport.loadFixture("body_measurement")

        try db.dbPool.write { conn in
            try IngestInbox.append(conn, source: .api, kind: ApiNormalizer.Kind.bodyMeasurement, payload: bodyPayload)
        }

        let firstPass = try ApiNormalizer.processPending(db.dbPool)
        XCTAssertEqual(firstPass.deferred, 1, "body measurement must defer without a known user id")

        try db.dbPool.read { conn in
            let undecoded = try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM ingest_inbox WHERE decoded_at IS NULL") ?? 0
            XCTAssertEqual(undecoded, 1, "deferred row must remain undecoded, not silently dropped")
        }

        // Profile now lands (as it would first, in a real sync ordering).
        let profilePayload = try TestSupport.loadFixture("profile")
        try db.dbPool.write { conn in
            try IngestInbox.append(conn, source: .api, kind: ApiNormalizer.Kind.profile, payload: profilePayload)
        }
        let secondPass = try ApiNormalizer.processPending(db.dbPool)
        XCTAssertEqual(secondPass.processed, 2, "both the new profile row and the previously-deferred body measurement")
        XCTAssertEqual(secondPass.upserted, 2)

        try db.dbPool.read { conn in
            let weight = try Double.fetchOne(conn, sql: "SELECT weight_kilogram FROM body_measurements WHERE user_id = 10129")
            XCTAssertEqual(weight ?? -1, 75.5, accuracy: 0.001)
        }
    }

    func testUnknownKindFailsGracefullyWithoutCorruptingOtherRows() throws {
        let db = try TestSupport.makeDatabase()
        try db.dbPool.write { conn in
            try IngestInbox.append(conn, source: .api, kind: "/v2/not-a-real-endpoint", payload: Data("{}".utf8))
            try IngestInbox.append(conn, source: .api, kind: ApiNormalizer.Kind.profile, payload: try TestSupport.loadFixture("profile"))
        }

        let stats = try ApiNormalizer.processPending(db.dbPool)
        XCTAssertEqual(stats.failed, 1)
        XCTAssertEqual(stats.upserted, 1, "one bad row must not block the rest of the batch")
    }
}
