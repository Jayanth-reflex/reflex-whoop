import Foundation
import GRDB

/// Writes `Documents/exports/<timestamp>/` per docs/design.md's "Export and
/// MCP" section: a CSV per normalized/derived table, a `VACUUM INTO` SQLite
/// snapshot (safe to copy from a live WAL database, unlike a plain file copy),
/// untouched raw payloads (`raw_api.jsonl`, `ble_sessions/<id>.bin`), and a
/// `manifest.json` tying it all together. This lands in `Documents/` (already
/// exposed via `UIFileSharingEnabled`), so the in-app Export button's share
/// sheet is the only other piece needed to get it onto a Mac.
enum Exporter {
    struct Result {
        let directory: URL
        let manifest: Manifest
    }

    struct Manifest: Codable {
        var exportedAt: Date
        var schemaVersion: [String] // applied migration names, in order
        var algoVersions: [String: Int]
        var rowCounts: [String: Int]
        var byteCounts: [String: Int]
        var dateRange: [String: [String: Int64]] // "api"/"ble" -> {"min":.., "max":..}
    }

    /// Every normalized + derived table worth a human-readable CSV. Deliberately
    /// excludes `ingest_inbox` and the `ts_chunk`/`ts_rollup_minute` blob tables —
    /// those are covered by the SQLite snapshot and the raw payload dumps below,
    /// where their binary content actually belongs.
    static let csvTables = [
        "cycles", "recoveries", "sleeps", "sleep_stage_summary", "sleep_need",
        "workouts", "workout_zone_durations", "body_measurements", "profile",
        "daily_metrics", "baselines", "correlations", "anomalies",
        "session_metrics", "ble_sessions",
    ]

    static func export(dbPool: DatabasePool, exportsRoot: URL) async throws -> Result {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let directory = exportsRoot.appendingPathComponent(stamp, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var rowCounts: [String: Int] = [:]
        var byteCounts: [String: Int] = [:]

        for table in csvTables {
            let (csv, count) = try await dbPool.read { db in
                try writeCSV(db, table: table)
            }
            let fileURL = directory.appendingPathComponent("\(table).csv")
            try csv.write(to: fileURL, atomically: true, encoding: .utf8)
            rowCounts[table] = count
            byteCounts["\(table).csv"] = csv.utf8.count
        }

        // VACUUM INTO can't run inside a transaction, so this can't go through
        // the usual `dbPool.write` (which wraps every call in one) —
        // `barrierWriteWithoutTransaction` also blocks concurrent readers for
        // the duration, which is what makes copying a live WAL database safe.
        let sqlitePath = directory.appendingPathComponent("reflexwhoop.sqlite").path
        try await dbPool.barrierWriteWithoutTransaction { db in
            try db.execute(sql: "VACUUM INTO ?", arguments: [sqlitePath])
        }
        byteCounts["reflexwhoop.sqlite"] = (try? FileManager.default.attributesOfItem(atPath: sqlitePath)[.size] as? Int) ?? 0

        let jsonlURL = directory.appendingPathComponent("raw_api.jsonl")
        let jsonlBytes = try await dbPool.read { db in try writeRawApiJsonl(db, to: jsonlURL) }
        byteCounts["raw_api.jsonl"] = jsonlBytes

        let bleDir = directory.appendingPathComponent("ble_sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: bleDir, withIntermediateDirectories: true)
        let bleBytes = try await dbPool.read { db in try writeBleSessionBins(db, to: bleDir) }
        byteCounts["ble_sessions"] = bleBytes

        let schemaVersion = try await dbPool.read { db in
            try Array(Migrator.makeMigrator().appliedMigrations(db)).sorted()
        }
        let algoVersions: [String: Int] = [
            "daily_metrics": DailyMetricsBuilder.algoVersion,
            "baselines": BaselineEngine.algoVersion,
            "readiness": ReadinessEngine.algoVersion,
            "anomalies": AnomalyEngine.algoVersion,
            "correlations": CorrelationEngine.algoVersion,
        ]
        let dateRange = try await dbPool.read { db -> [String: [String: Int64]] in
            var range: [String: [String: Int64]] = [:]
            if let row = try Row.fetchOne(db, sql: "SELECT MIN(start) AS lo, MAX(start) AS hi FROM cycles"),
               let lo: Int64 = row["lo"], let hi: Int64 = row["hi"] {
                range["api"] = ["min": lo, "max": hi]
            }
            if let row = try Row.fetchOne(db, sql: "SELECT MIN(started_at) AS lo, MAX(started_at) AS hi FROM ble_sessions"),
               let lo: Int64 = row["lo"], let hi: Int64 = row["hi"] {
                range["ble"] = ["min": lo, "max": hi]
            }
            return range
        }

        let manifest = Manifest(
            exportedAt: Date(),
            schemaVersion: schemaVersion,
            algoVersions: algoVersions,
            rowCounts: rowCounts,
            byteCounts: byteCounts,
            dateRange: dateRange
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: directory.appendingPathComponent("manifest.json"))

        return Result(directory: directory, manifest: manifest)
    }

    // MARK: - CSV

    private static func writeCSV(_ db: GRDB.Database, table: String) throws -> (String, Int) {
        let columns = try db.columns(in: table).map(\.name)
        var csv = columns.map(csvEscape).joined(separator: ",") + "\n"
        var count = 0
        let cursor = try Row.fetchCursor(db, sql: "SELECT * FROM \(table)")
        while let row = try cursor.next() {
            let fields = columns.map { csvField(row[$0] as DatabaseValue) }
            csv += fields.joined(separator: ",") + "\n"
            count += 1
        }
        return (csv, count)
    }

    private static func csvField(_ value: DatabaseValue) -> String {
        switch value.storage {
        case .null: return ""
        case .int64(let i): return String(i)
        case .double(let d): return String(d)
        case .string(let s): return csvEscape(s)
        case .blob(let data): return csvEscape("<\(data.count) bytes>")
        }
    }

    private static func csvEscape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else { return field }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    // MARK: - Raw payloads

    /// One JSON object per line: the inbox row's bookkeeping fields plus the
    /// original WHOOP API payload, decompressed and re-parsed so it comes out
    /// as real embedded JSON rather than an escaped string blob.
    private static func writeRawApiJsonl(_ db: GRDB.Database, to url: URL) throws -> Int {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        var totalBytes = 0

        let cursor = try Row.fetchCursor(db, sql: "SELECT seq, kind, received_at, payload, codec FROM ingest_inbox WHERE source = 'api' ORDER BY seq")
        while let row = try cursor.next() {
            let payload = IngestInbox.payload(for: row)
            guard let payloadObject = try? JSONSerialization.jsonObject(with: payload) else { continue }
            let line: [String: Any] = [
                "seq": row["seq"] as Int64,
                "kind": row["kind"] as String,
                "received_at": row["received_at"] as Int64,
                "payload": payloadObject,
            ]
            guard var data = try? JSONSerialization.data(withJSONObject: line) else { continue }
            data.append(0x0A) // newline
            handle.write(data)
            totalBytes += data.count
        }
        return totalBytes
    }

    /// Simple self-describing binary dump per BLE session, so it's replayable
    /// without database access: `[u8 kindLen][kind ascii][i64 LE receivedAt]
    /// [u32 LE payloadLen][payload bytes]`, repeated for every inbox row that
    /// fell within the session's time window.
    private static func writeBleSessionBins(_ db: GRDB.Database, to directory: URL) throws -> Int {
        var totalBytes = 0
        let sessions = try Row.fetchAll(db, sql: "SELECT id, started_at, ended_at FROM ble_sessions")
        for session in sessions {
            let id: String = session["id"]
            let startedAt: Int64 = session["started_at"]
            let endedAt: Int64 = (session["ended_at"] as Int64?) ?? Int64.max

            var blob = Data()
            let cursor = try Row.fetchCursor(
                db,
                sql: "SELECT kind, received_at, payload FROM ingest_inbox WHERE source = 'ble' AND received_at BETWEEN ? AND ? ORDER BY seq",
                arguments: [startedAt, endedAt]
            )
            while let row = try cursor.next() {
                let kind: String = row["kind"]
                let receivedAt: Int64 = row["received_at"]
                let payload: Data = row["payload"]
                let kindBytes = Data(kind.utf8)
                blob.append(UInt8(kindBytes.count))
                blob.append(kindBytes)
                withUnsafeBytes(of: receivedAt.littleEndian) { blob.append(contentsOf: $0) }
                withUnsafeBytes(of: UInt32(payload.count).littleEndian) { blob.append(contentsOf: $0) }
                blob.append(payload)
            }
            let fileURL = directory.appendingPathComponent("\(id).bin")
            try blob.write(to: fileURL)
            totalBytes += blob.count
        }
        return totalBytes
    }
}
