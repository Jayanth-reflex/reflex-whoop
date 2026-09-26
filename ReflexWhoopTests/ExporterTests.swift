import XCTest
import GRDB
@testable import ReflexWhoop

final class ExporterTests: XCTestCase {
    private func tempExportsRoot() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("reflexwhoop-exports-test-\(UUID().uuidString)", isDirectory: true)
        return url
    }

    func testExportWritesCsvSqliteJsonlAndManifestForAPopulatedDatabase() async throws {
        let db = try TestSupport.makeDatabase()
        let payload = try TestSupport.loadFixture("cycle_page")
        let page = try JSONDecoder().decode(PaginatedResponse<Cycle>.self, from: payload)

        try await db.dbPool.write { conn in
            let seq = try IngestInbox.append(conn, source: .api, kind: "cycle_page", payload: payload)
            _ = try RecordDAO.upsert(conn, cycle: page.records[0], inboxSeq: seq)
        }

        let root = tempExportsRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let result = try await Exporter.export(dbPool: db.dbPool, exportsRoot: root)

        XCTAssertEqual(result.manifest.rowCounts["cycles"], 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.directory.appendingPathComponent("cycles.csv").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.directory.appendingPathComponent("reflexwhoop.sqlite").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.directory.appendingPathComponent("manifest.json").path))

        let cyclesCsv = try String(contentsOf: result.directory.appendingPathComponent("cycles.csv"), encoding: .utf8)
        let lines = cyclesCsv.split(separator: "\n")
        XCTAssertEqual(lines.count, 2, "header + one data row")
        XCTAssertTrue(lines[0].contains("id"), "header row should name the columns")

        let jsonlURL = result.directory.appendingPathComponent("raw_api.jsonl")
        let jsonl = try String(contentsOf: jsonlURL, encoding: .utf8)
        XCTAssertTrue(jsonl.contains("cycle_page"))

        XCTAssertFalse(result.manifest.schemaVersion.isEmpty)
        XCTAssertEqual(result.manifest.algoVersions["daily_metrics"], DailyMetricsBuilder.algoVersion)
    }

    func testExportOfAnEmptyDatabaseStillProducesValidStructure() async throws {
        let db = try TestSupport.makeDatabase()
        let root = tempExportsRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let result = try await Exporter.export(dbPool: db.dbPool, exportsRoot: root)

        for table in Exporter.csvTables {
            XCTAssertEqual(result.manifest.rowCounts[table], 0)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.directory.appendingPathComponent("reflexwhoop.sqlite").path))
    }

    func testBleSessionProducesABinFileNamedByItsSessionID() async throws {
        let db = try TestSupport.makeDatabase()
        let sessionID = "test-session-1"
        try await db.dbPool.write { conn in
            try conn.execute(
                sql: "INSERT INTO ble_sessions (id, started_at, mode, channels_json) VALUES (?, ?, 'hr', '[]')",
                arguments: [sessionID, 1_000]
            )
            try IngestInbox.append(conn, source: .ble, kind: "FD4B0005", payload: Data([0xAA, 0x01]), receivedAt: Date(timeIntervalSince1970: 1_000))
        }

        let root = tempExportsRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let result = try await Exporter.export(dbPool: db.dbPool, exportsRoot: root)

        let binURL = result.directory.appendingPathComponent("ble_sessions/\(sessionID).bin")
        XCTAssertTrue(FileManager.default.fileExists(atPath: binURL.path))
        let bytes = try Data(contentsOf: binURL)
        XCTAssertFalse(bytes.isEmpty)
    }

    /// The phone's export was 1.4 GB of band files for 72 MB of band data. Sessions the
    /// app never closed have no `ended_at`, and the exporter treated that as "until the
    /// end of time", so each one re-dumped every frame recorded after it. A session with
    /// no end owns frames only up to the next session's start, as the normalizer
    /// already has it, and every frame lands in exactly one file.
    func testEachBandFrameIsExportedExactlyOnceWhenSessionsWereNeverClosed() async throws {
        let db = try TestSupport.makeDatabase()
        try await db.dbPool.write { conn in
            for (id, start, end) in [("a", 1_000, nil), ("b", 2_000, nil), ("c", 3_000, 3_500)] as [(String, Int64, Int64?)] {
                try conn.execute(
                    sql: "INSERT INTO ble_sessions (id, started_at, ended_at, mode, channels_json) VALUES (?, ?, ?, 'hr', '[]')",
                    arguments: [id, start, end]
                )
            }
            // 500 is before any session and 3_600 is after the last one closed.
            for at in [500, 1_000, 1_500, 2_000, 2_500, 3_000, 3_400, 3_600] {
                try IngestInbox.append(conn, source: .ble, kind: "FD4B0005", payload: Data([UInt8(at / 100)]),
                                       receivedAt: Date(timeIntervalSince1970: TimeInterval(at)))
            }
        }

        let root = tempExportsRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let result = try await Exporter.export(dbPool: db.dbPool, exportsRoot: root)

        func frameTimes(_ name: String) throws -> [Int64] {
            let data = try Data(contentsOf: result.directory.appendingPathComponent("ble_sessions/\(name).bin"))
            return try BinRecord.parseAll(data).map(\.receivedAt)
        }
        XCTAssertEqual(try frameTimes("a"), [1_000, 1_500], "an unclosed session stops where the next one starts")
        XCTAssertEqual(try frameTimes("b"), [2_000, 2_500])
        XCTAssertEqual(try frameTimes("c"), [3_000, 3_400])
        XCTAssertEqual(try frameTimes("unassigned"), [500, 3_600], "frames outside every session are still exported, once")
    }

    /// The archive only grows, so a new export holds everything an older one did. Keeping
    /// every copy is how four exports came to fill 1.6 GB of the phone.
    func testANewExportReplacesEarlierCopies() async throws {
        let db = try TestSupport.makeDatabase()
        let root = tempExportsRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let earlier = root.appendingPathComponent("2026-09-08 at 04.54.10", isDirectory: true)
        try FileManager.default.createDirectory(at: earlier, withIntermediateDirectories: true)
        try Data([0x01]).write(to: earlier.appendingPathComponent("reflexwhoop.sqlite"))

        let result = try await Exporter.export(dbPool: db.dbPool, exportsRoot: root)

        XCTAssertFalse(FileManager.default.fileExists(atPath: earlier.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [result.directory.lastPathComponent])
    }
}

/// Reads the exporter's band record format back:
/// `[u8 kindLen][kind ascii][i64 LE receivedAt][u32 LE payloadLen][payload]`.
private struct BinRecord {
    let kind: String
    let receivedAt: Int64
    let payload: Data

    struct Truncated: Error {}

    static func parseAll(_ data: Data) throws -> [BinRecord] {
        let bytes = [UInt8](data)
        var records: [BinRecord] = []
        var i = 0
        func take(_ n: Int) throws -> ArraySlice<UInt8> {
            guard i + n <= bytes.count else { throw Truncated() }
            defer { i += n }
            return bytes[i..<(i + n)]
        }
        func littleEndian<T: FixedWidthInteger>(_ slice: ArraySlice<UInt8>, as: T.Type) -> T {
            slice.reversed().reduce(T(0)) { $0 << 8 | T($1) }
        }
        while i < bytes.count {
            let kindLength = Int(try take(1).first!)
            let kind = String(decoding: try take(kindLength), as: UTF8.self)
            let receivedAt = littleEndian(try take(8), as: Int64.self)
            let payloadLength = Int(littleEndian(try take(4), as: UInt32.self))
            records.append(BinRecord(kind: kind, receivedAt: receivedAt, payload: Data(try take(payloadLength))))
        }
        return records
    }
}
