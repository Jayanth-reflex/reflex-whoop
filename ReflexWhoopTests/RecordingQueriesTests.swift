import XCTest
import GRDB
@testable import ReflexWhoop

final class RecordingQueriesTests: XCTestCase {
    private var database: ReflexWhoop.Database!

    override func setUpWithError() throws {
        database = try TestSupport.makeDatabase()
        try database.dbPool.write { db in
            try db.execute(sql: "INSERT INTO ble_sessions (id, started_at, mode) VALUES ('old', 1000, 'continuous')")
            try db.execute(sql: "INSERT INTO ble_sessions (id, started_at, mode) VALUES ('new', 5000, 'continuous')")
            try db.execute(
                sql: """
                INSERT INTO session_metrics (session_id, algo_version, computed_at, hr_mean, hr_min, hr_max, hr_sample_count)
                VALUES ('new', 1, 0, 71.4, 59, 104, 1104)
                """
            )
            for (offset, mean) in [(0, 67.0), (60, 62.0), (600, 99.0)] {
                try db.execute(
                    sql: """
                    INSERT INTO ts_rollup_minute (channel, session_id, minute_start, mean_val, min_val, max_val, sample_count)
                    VALUES (?, 'new', ?, ?, ?, ?, 60)
                    """,
                    arguments: [BleNormalizer.Channel.heartRate, 5040 + offset, mean, mean - 2, mean + 2]
                )
            }
        }
    }

    /// An empty recording is a fact about the band, so it stays in the list.
    func testRecentIsNewestFirstAndKeepsEmptySessions() throws {
        let recordings = try database.dbPool.read { try RecordingQueries.recent($0, limit: nil) }
        XCTAssertEqual(recordings.map(\.id), ["new", "old"])
        XCTAssertEqual(recordings[1].readingCount, 0)
        XCTAssertNil(recordings[1].averageBpm)
        XCTAssertNil(recordings[1].span)
    }

    func testSummaryTakesItsSpanFromTheMinutesWithReadings() throws {
        let recording = try XCTUnwrap(try database.dbPool.read { try RecordingQueries.recent($0, limit: 1) }.first)
        XCTAssertEqual(recording.id, "new")
        XCTAssertEqual(recording.minutesWithReadings, 3)
        XCTAssertEqual(recording.readingCount, 1104)
        XCTAssertEqual(recording.lowestBpm, 59)
        XCTAssertEqual(recording.highestBpm, 104)
        XCTAssertEqual(recording.firstReadingAt, Date(timeIntervalSince1970: 5040))
        XCTAssertEqual(recording.span, 600)
    }

    func testMinuteReadingsAreChronological() throws {
        let readings = try database.dbPool.read { try RecordingQueries.minuteReadings($0, sessionID: "new") }
        XCTAssertEqual(readings.map(\.bpm), [67, 62, 99])
        XCTAssertEqual(readings.first?.time, Date(timeIntervalSince1970: 5040))
    }
}
