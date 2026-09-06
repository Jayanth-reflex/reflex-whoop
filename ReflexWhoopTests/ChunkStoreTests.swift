import XCTest
import GRDB
@testable import ReflexWhoop

final class ChunkStoreTests: XCTestCase {
    func testWriteThenReadRoundTripsWithinOneHourBucket() throws {
        let db = try TestSupport.makeDatabase()
        let sessionId = UUID().uuidString
        let base: Int64 = 1_700_000_000

        try db.dbPool.write { conn in
            try conn.execute(
                sql: "INSERT INTO ble_sessions (id, started_at, mode) VALUES (?, ?, 'hr_rr')",
                arguments: [sessionId, base]
            )
            let samples = (0..<600).map { Sample(timestamp: base + Int64($0), value: Int64(60 + $0 % 40)) }
            try ChunkStore.write(conn, channel: "hr", sessionID: sessionId, samples: samples, nominalHz: 1.0)
        }

        try db.dbPool.read { conn in
            let read = try ChunkStore.read(conn, channel: "hr", sessionID: sessionId, startTs: base, endTs: base + 600)
            XCTAssertEqual(read.count, 600)
            XCTAssertEqual(Set(read.map(\.value)), Set((0..<600).map { Int64(60 + $0 % 40) }))
        }
    }

    func testSamplesSpanningTwoHourBucketsSplitCorrectly() throws {
        let db = try TestSupport.makeDatabase()
        let sessionId = UUID().uuidString
        let hourBoundary: Int64 = 3600

        try db.dbPool.write { conn in
            try conn.execute(sql: "INSERT INTO ble_sessions (id, started_at, mode) VALUES (?, 0, 'hr_rr')", arguments: [sessionId])
            let samples = [
                Sample(timestamp: hourBoundary - 10, value: 1),
                Sample(timestamp: hourBoundary - 5, value: 2),
                Sample(timestamp: hourBoundary + 5, value: 3),
                Sample(timestamp: hourBoundary + 10, value: 4),
            ]
            try ChunkStore.write(conn, channel: "hr", sessionID: sessionId, samples: samples, nominalHz: 1.0)
        }

        try db.dbPool.read { conn in
            let chunkCount = try Int.fetchOne(
                conn, sql: "SELECT COUNT(*) FROM ts_chunk WHERE channel = 'hr' AND session_id = ?", arguments: [sessionId]
            ) ?? 0
            XCTAssertEqual(chunkCount, 2, "samples either side of the hour boundary must land in separate buckets")
        }
    }

    func testMinuteRollupSummarizesCorrectly() throws {
        let db = try TestSupport.makeDatabase()
        let sessionId = UUID().uuidString

        try db.dbPool.write { conn in
            try conn.execute(sql: "INSERT INTO ble_sessions (id, started_at, mode) VALUES (?, 0, 'hr_rr')", arguments: [sessionId])
            let samples = (0..<60).map { Sample(timestamp: Int64($0), value: Int64($0)) } // one minute, values 0-59
            try ChunkStore.write(conn, channel: "hr", sessionID: sessionId, samples: samples, nominalHz: 1.0)
        }

        try db.dbPool.read { conn in
            let row = try Row.fetchOne(
                conn, sql: "SELECT min_val, max_val, mean_val, sample_count FROM ts_rollup_minute WHERE channel = 'hr' AND session_id = ?",
                arguments: [sessionId]
            )
            XCTAssertEqual(row?["min_val"], 0.0)
            XCTAssertEqual(row?["max_val"], 59.0)
            XCTAssertEqual(row?["sample_count"], 60)
        }
    }
}
