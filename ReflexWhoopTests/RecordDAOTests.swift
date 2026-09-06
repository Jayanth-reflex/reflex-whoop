import XCTest
import GRDB
@testable import ReflexWhoop

/// Verifies the content-hash skip logic that makes the sync engine's 7-day
/// re-scoring lookback cheap: re-upserting an unchanged record must be a no-op,
/// and a genuinely changed record (e.g. PENDING_SCORE -> SCORED) must write through.
final class RecordDAOTests: XCTestCase {
    func testUpsertingIdenticalCycleTwiceIsANoOp() throws {
        let db = try TestSupport.makeDatabase()
        let payload = try TestSupport.loadFixture("cycle_page")
        let page = try JSONDecoder().decode(PaginatedResponse<Cycle>.self, from: payload)
        let cycle = page.records[0]

        try db.dbPool.write { conn in
            XCTAssertTrue(try RecordDAO.upsert(conn, cycle: cycle, inboxSeq: 1), "first upsert should write")
            XCTAssertFalse(try RecordDAO.upsert(conn, cycle: cycle, inboxSeq: 2), "identical re-upsert should be skipped")
        }

        try db.dbPool.read { conn in
            let count = try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM cycles") ?? 0
            XCTAssertEqual(count, 1, "must never duplicate a row on re-upsert")
        }
    }

    func testPendingScoreCycleTracksInPendingScoresThenClearsOnceScored() throws {
        let db = try TestSupport.makeDatabase()
        let payload = try TestSupport.loadFixture("cycle_page")
        let page = try JSONDecoder().decode(PaginatedResponse<Cycle>.self, from: payload)
        let pendingCycle = page.records[1] // fixture's second record is PENDING_SCORE

        try db.dbPool.write { conn in
            _ = try RecordDAO.upsert(conn, cycle: pendingCycle, inboxSeq: 1)
        }
        try db.dbPool.read { conn in
            let pending = try Int.fetchOne(
                conn, sql: "SELECT COUNT(*) FROM pending_scores WHERE resource = 'cycle' AND record_id = ?",
                arguments: [String(pendingCycle.id)]
            ) ?? 0
            XCTAssertEqual(pending, 1)
        }

        // Re-arrives later, now scored — the re-fetch-and-upsert path a real sync does.
        let scoredJSON = """
        {"id": \(pendingCycle.id), "user_id": \(pendingCycle.userId), \
        "created_at": "2026-09-02T02:25:44.774Z", "updated_at": "2026-09-02T14:25:44.774Z", \
        "start": "2026-09-02T02:25:44.774Z", "end": "2026-09-02T10:25:44.774Z", \
        "timezone_offset": "-05:00", "score_state": "SCORED", \
        "score": {"strain": 6.1, "kilojoule": 9000.0, "average_heart_rate": 70, "max_heart_rate": 150}}
        """.data(using: .utf8)!
        let scoredCycle = try JSONDecoder().decode(Cycle.self, from: scoredJSON)

        try db.dbPool.write { conn in
            let wrote = try RecordDAO.upsert(conn, cycle: scoredCycle, inboxSeq: 2)
            XCTAssertTrue(wrote, "score_state transition must always be treated as a change")
        }
        try db.dbPool.read { conn in
            let pending = try Int.fetchOne(
                conn, sql: "SELECT COUNT(*) FROM pending_scores WHERE resource = 'cycle' AND record_id = ?",
                arguments: [String(pendingCycle.id)]
            ) ?? 0
            XCTAssertEqual(pending, 0, "pending_scores entry must clear once scored")

            let state = try String.fetchOne(conn, sql: "SELECT score_state FROM cycles WHERE id = ?", arguments: [String(pendingCycle.id)])
            XCTAssertEqual(state, "SCORED")
        }
    }

    func testSleepUpsertPopulatesStageSummaryAndNeedTables() throws {
        let db = try TestSupport.makeDatabase()
        let payload = try TestSupport.loadFixture("sleep_page")
        let page = try JSONDecoder().decode(PaginatedResponse<Sleep>.self, from: payload)
        let sleep = page.records[0]

        try db.dbPool.write { conn in
            _ = try RecordDAO.upsert(conn, sleep: sleep, inboxSeq: 1)
        }

        try db.dbPool.read { conn in
            let remMilli = try Int.fetchOne(
                conn, sql: "SELECT total_rem_sleep_time_milli FROM sleep_stage_summary WHERE sleep_id = ?",
                arguments: [sleep.id]
            )
            XCTAssertEqual(remMilli, sleep.score?.stageSummary.totalRemSleepTimeMilli)

            let baseline = try Int.fetchOne(
                conn, sql: "SELECT baseline_milli FROM sleep_need WHERE sleep_id = ?", arguments: [sleep.id]
            )
            XCTAssertEqual(baseline, sleep.score?.sleepNeeded.baselineMilli)
        }
    }

    func testWorkoutUpsertPopulatesZoneDurations() throws {
        let db = try TestSupport.makeDatabase()
        let payload = try TestSupport.loadFixture("workout_page")
        let page = try JSONDecoder().decode(PaginatedResponse<Workout>.self, from: payload)
        let workout = page.records[0]

        try db.dbPool.write { conn in
            _ = try RecordDAO.upsert(conn, workout: workout, inboxSeq: 1)
        }

        try db.dbPool.read { conn in
            let zoneThree = try Int.fetchOne(
                conn, sql: "SELECT zone_three_milli FROM workout_zone_durations WHERE workout_id = ?",
                arguments: [workout.id]
            )
            XCTAssertEqual(zoneThree, workout.score?.zoneDurations?.zoneThreeMilli)
        }
    }

    func testCycleUpsertMarksDirtyDay() throws {
        let db = try TestSupport.makeDatabase()
        let payload = try TestSupport.loadFixture("cycle_page")
        let page = try JSONDecoder().decode(PaginatedResponse<Cycle>.self, from: payload)
        let cycle = page.records[0]

        try db.dbPool.write { conn in
            _ = try RecordDAO.upsert(conn, cycle: cycle, inboxSeq: 1)
        }
        try db.dbPool.read { conn in
            let day = RecordDAO.dayString(for: cycle.start)
            let marked = try Int.fetchOne(
                conn, sql: "SELECT COUNT(*) FROM dirty_days WHERE day = ? AND reason = 'cycle'", arguments: [day]
            ) ?? 0
            XCTAssertEqual(marked, 1)
        }
    }
}
