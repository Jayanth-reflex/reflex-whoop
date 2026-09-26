import XCTest
import GRDB
@testable import ReflexWhoop

/// Band frames used to be written one transaction each — about 100,000 a day — which
/// iOS flagged for dirtying 1 GB of flash in six hours. The buffer batches them, and
/// has to do so without reordering frames (reassembly replays them in `seq` order) or
/// losing a failed write silently.
@MainActor
final class InboxWriteBufferTests: XCTestCase {
    private var database: ReflexWhoop.Database!

    override func setUp() async throws {
        database = try TestSupport.makeDatabase()
    }

    private func frame(_ i: Int) -> (payload: Data, at: Date) {
        (Data([UInt8(i % 256), UInt8(i / 256)]), Date(timeIntervalSince1970: 1_000 + TimeInterval(i) / 4))
    }

    private func storedPayloads() async throws -> [Data] {
        try await database.dbPool.read { db in
            try Data.fetchAll(db, sql: "SELECT payload FROM ingest_inbox WHERE source = 'ble' ORDER BY seq")
        }
    }

    func testFramesKeepArrivalOrderAcrossManyBatches() async throws {
        let buffer = InboxWriteBuffer(dbPool: database.dbPool, maxFrames: 7, maxAge: 60)
        for i in 0..<500 {
            let (payload, at) = frame(i)
            buffer.append(kind: "FD4B0005", payload: payload, receivedAt: at)
        }
        buffer.flush()
        await buffer.drain()

        let stored = try await storedPayloads()
        XCTAssertEqual(stored, (0..<500).map { frame($0).payload })
    }

    func testFramesWaitInMemoryUntilTheBatchIsFull() async throws {
        let buffer = InboxWriteBuffer(dbPool: database.dbPool, maxFrames: 4, maxAge: 60)
        for i in 0..<3 {
            let (payload, at) = frame(i)
            buffer.append(kind: "FD4B0005", payload: payload, receivedAt: at)
        }
        await buffer.drain()
        let beforeFull = try await storedPayloads()
        XCTAssertEqual(beforeFull.count, 0, "three frames are not a batch of four")

        let (payload, at) = frame(3)
        buffer.append(kind: "FD4B0005", payload: payload, receivedAt: at)
        await buffer.drain()
        let afterFull = try await storedPayloads()
        XCTAssertEqual(afterFull.count, 4)
    }

    /// A slow trickle still reaches the database: the oldest frame's age forces the batch
    /// out even when it never fills.
    func testAnAgedFrameForcesTheBatchOut() async throws {
        let buffer = InboxWriteBuffer(dbPool: database.dbPool, maxFrames: 64, maxAge: 10)
        let start = Date(timeIntervalSince1970: 1_000)
        buffer.append(kind: "FD4B0005", payload: Data([1]), receivedAt: start)
        buffer.append(kind: "FD4B0005", payload: Data([2]), receivedAt: start.addingTimeInterval(10))
        await buffer.drain()

        let stored = try await storedPayloads()
        XCTAssertEqual(stored, [Data([1]), Data([2])])
    }

    /// The per-frame writes used `try?`, so a failure left no trace. A batch that can't be
    /// written is counted, so the session can record how many frames it lost.
    func testFramesInAFailedBatchAreCountedNotSilentlyDropped() async throws {
        try await database.dbPool.write { db in
            try db.execute(sql: "CREATE TRIGGER refuse BEFORE INSERT ON ingest_inbox BEGIN SELECT RAISE(ABORT, 'refused'); END")
        }
        let buffer = InboxWriteBuffer(dbPool: database.dbPool, maxFrames: 5, maxAge: 60)
        for i in 0..<5 {
            let (payload, at) = frame(i)
            buffer.append(kind: "FD4B0005", payload: payload, receivedAt: at)
        }
        await buffer.drain()

        XCTAssertEqual(buffer.failedFrameCount, 5)
    }
}
