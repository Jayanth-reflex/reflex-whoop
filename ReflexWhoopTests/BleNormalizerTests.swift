import XCTest
import GRDB
@testable import ReflexWhoop

final class BleNormalizerTests: XCTestCase {
    private var database: ReflexWhoop.Database!

    override func setUpWithError() throws {
        database = try TestSupport.makeDatabase()
    }

    /// Builds a real, CRC-valid `0x28` realtime-HR frame the same way the band
    /// does — through `Gen5Envelope.encode`, so these tests exercise the actual
    /// framing rather than a hand-rolled approximation of it.
    private func hrFrame(bpm: UInt8) -> Data {
        var inner = Data([0x28, 0x02, 0x00, 0xe2, 0x9e, 0x6a, 0xb8, 0x7e])
        inner.append(bpm)
        inner.append(Data(repeating: 0, count: 11))
        return Gen5Envelope.encode(field: 1, inner: inner)
    }

    private func insertSession(id: String, start: Int64, end: Int64?) throws {
        try database.dbPool.write { db in
            try db.execute(
                sql: """
                INSERT INTO ble_sessions (id, started_at, ended_at, mode, sample_count, dropped_count, byte_count)
                VALUES (?, ?, ?, 'test', 0, 0, 0)
                """,
                arguments: [id, start, end]
            )
        }
    }

    private func appendFrame(_ payload: Data, at receivedAt: Int64, kind: String = "fd4b0005") throws {
        try database.dbPool.write { db in
            try IngestInbox.append(
                db, source: .ble, kind: kind, payload: payload,
                receivedAt: Date(timeIntervalSince1970: TimeInterval(receivedAt))
            )
        }
    }

    func testDecodesHeartRateFramesIntoSamplesAndMetrics() throws {
        try insertSession(id: "s1", start: 1000, end: 1100)
        for (offset, bpm) in [(0, UInt8(60)), (1, 70), (2, 80)] {
            try appendFrame(hrFrame(bpm: bpm), at: 1000 + Int64(offset))
        }

        let stats = try BleNormalizer.processPending(database.dbPool)

        XCTAssertEqual(stats.sessionsProcessed, 1)
        XCTAssertEqual(stats.framesDecoded, 3)
        XCTAssertEqual(stats.samplesWritten, 3)

        try database.dbPool.read { db in
            let row = try Row.fetchOne(db, sql: "SELECT * FROM session_metrics WHERE session_id = 's1'")
            XCTAssertEqual(row?["hr_sample_count"] as Int?, 3)
            XCTAssertEqual(row?["hr_min"] as Int?, 60)
            XCTAssertEqual(row?["hr_max"] as Int?, 80)
            XCTAssertEqual(row?["hr_mean"] as Double?, 70.0)
            XCTAssertEqual(row?["signal_quality"] as Double?, 1.0)
        }
    }

    /// The HRV columns must stay NULL rather than being filled with a plausible
    /// substitute — there is no RR channel, so any number there would be
    /// fabricated (docs/design.md: "never fabricate a value").
    func testHrvColumnsStayNullWithoutAnRrChannel() throws {
        try insertSession(id: "s1", start: 1000, end: 1100)
        try appendFrame(hrFrame(bpm: 65), at: 1000)

        try BleNormalizer.processPending(database.dbPool)

        try database.dbPool.read { db in
            let row = try Row.fetchOne(db, sql: "SELECT * FROM session_metrics WHERE session_id = 's1'")
            XCTAssertNil(row?["rmssd_milli"] as Double?)
            XCTAssertNil(row?["sdnn_milli"] as Double?)
            XCTAssertNil(row?["pnn50_pct"] as Double?)
            XCTAssertNil(row?["dfa_alpha1"] as Double?)
            XCTAssertNil(row?["respiratory_rate"] as Double?)
        }
    }

    func testWritesQueryableMinuteRollup() throws {
        try insertSession(id: "s1", start: 1000, end: 1100)
        try appendFrame(hrFrame(bpm: 60), at: 1000)
        try appendFrame(hrFrame(bpm: 80), at: 1001)

        try BleNormalizer.processPending(database.dbPool)

        try database.dbPool.read { db in
            let row = try Row.fetchOne(
                db, sql: "SELECT * FROM ts_rollup_minute WHERE session_id = 's1' AND channel = 'hr'"
            )
            XCTAssertEqual(row?["sample_count"] as Int?, 2)
            XCTAssertEqual(row?["mean_val"] as Double?, 70.0)
        }
    }

    /// Frames whose packet type has no confirmed decoder are counted, not
    /// guessed at — that count is the firmware-drift canary.
    func testUnmappedFramesAreCountedNotDecoded() throws {
        try insertSession(id: "s1", start: 1000, end: 1100)
        try appendFrame(hrFrame(bpm: 70), at: 1000)
        try appendFrame(Gen5Envelope.encode(field: 1, inner: Data([0x2F, 0x01, 0x00, 0x00])), at: 1001)

        let stats = try BleNormalizer.processPending(database.dbPool)

        XCTAssertEqual(stats.framesDecoded, 1)
        XCTAssertEqual(stats.framesUnmapped, 1)
        try database.dbPool.read { db in
            let quality = try Double.fetchOne(
                db, sql: "SELECT signal_quality FROM session_metrics WHERE session_id = 's1'"
            )
            XCTAssertEqual(quality, 0.5)
        }
    }

    func testProcessingIsIdempotent() throws {
        try insertSession(id: "s1", start: 1000, end: 1100)
        try appendFrame(hrFrame(bpm: 70), at: 1000)

        try BleNormalizer.processPending(database.dbPool)
        let second = try BleNormalizer.processPending(database.dbPool)

        XCTAssertEqual(second.sessionsProcessed, 0, "nothing left undecoded, so nothing to redo")
        try database.dbPool.read { db in
            let count = try Int.fetchOne(db, sql: "SELECT hr_sample_count FROM session_metrics WHERE session_id = 's1'")
            XCTAssertEqual(count, 1, "a second pass must not double-count")
        }
    }

    func testReplayRederivesFromInboxBytes() throws {
        try insertSession(id: "s1", start: 1000, end: 1100)
        try appendFrame(hrFrame(bpm: 70), at: 1000)
        try BleNormalizer.processPending(database.dbPool)

        let stats = try BleNormalizer.replay(database.dbPool)

        XCTAssertEqual(stats.sessionsProcessed, 1)
        XCTAssertEqual(stats.samplesWritten, 1)
        try database.dbPool.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT hr_sample_count FROM session_metrics WHERE session_id = 's1'"), 1)
        }
    }

    /// A session killed mid-recording never got an `ended_at`. Its frames still
    /// belong to it, bounded by whenever the next session started.
    func testUnclosedSessionOwnsFramesUpToTheNextSession() throws {
        try insertSession(id: "open", start: 1000, end: nil)
        try insertSession(id: "next", start: 2000, end: 2100)
        try appendFrame(hrFrame(bpm: 70), at: 1500)
        try appendFrame(hrFrame(bpm: 90), at: 2050)

        try BleNormalizer.processPending(database.dbPool)

        try database.dbPool.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT hr_max FROM session_metrics WHERE session_id = 'open'"), 70)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT hr_max FROM session_metrics WHERE session_id = 'next'"), 90)
        }
    }

    /// CBOR device metadata is not envelope-framed; feeding it to the
    /// reassembler would corrupt the frame buffer around it.
    func testDeviceMetadataFramesDoNotCorruptReassembly() throws {
        try insertSession(id: "s1", start: 1000, end: 1100)
        try appendFrame(Data([0x62, 0x68, 0x69]), at: 1000, kind: Ble.unknown0007CharacteristicUUID.uuidString)
        try appendFrame(hrFrame(bpm: 70), at: 1001)

        let stats = try BleNormalizer.processPending(database.dbPool)

        XCTAssertEqual(stats.framesDecoded, 1)
        XCTAssertEqual(stats.framesCorrupt, 0)
    }

    func testFramesOutsideAnySessionAreMarkedDecodedNotLost() throws {
        try insertSession(id: "s1", start: 1000, end: 1100)
        try appendFrame(hrFrame(bpm: 70), at: 5000)

        let stats = try BleNormalizer.processPending(database.dbPool)

        XCTAssertEqual(stats.orphanRows, 1)
        try database.dbPool.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ingest_inbox WHERE decoded_at IS NULL"), 0)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ingest_inbox"), 1, "the bytes are kept")
        }
    }
}
