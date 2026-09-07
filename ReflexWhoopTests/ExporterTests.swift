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
}
