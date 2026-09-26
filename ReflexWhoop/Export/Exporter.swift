import Foundation
import GRDB

/// Writes `Documents/exports/<timestamp>/` per docs/ARCHITECTURE.md's "Export and
/// MCP" section: a CSV per normalized/derived table, a `VACUUM INTO` SQLite
/// snapshot (safe to copy from a live WAL database, unlike a plain file copy),
/// untouched raw payloads (`raw_api.jsonl`, `ble_sessions/<id>.bin`), and a
/// `manifest.json` tying it all together. This lands in `Documents/` (already
/// exposed via `UIFileSharingEnabled`), so the in-app Export button's share
/// sheet is the only other piece needed to get it onto a Mac.
///
/// A finished export replaces the ones before it. The archive only grows, so the
/// newest copy holds everything an older one did; keeping them all is how four
/// exports once filled 1.6 GB of a phone.
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

    /// Local time, sortable, and free of colons (Finder shows them as slashes):
    /// "2026-09-14 at 01.23.31".
    static func folderName(for date: Date, timeZone: TimeZone = .current) -> String {
        let style = Date.VerbatimFormatStyle(
            format: "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) at \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)).\(minute: .twoDigits).\(second: .twoDigits)",
            timeZone: timeZone,
            calendar: Calendar(identifier: .gregorian)
        )
        return date.formatted(style)
    }

    static func export(dbPool: DatabasePool, exportsRoot: URL) async throws -> Result {
        let directory = exportsRoot.appendingPathComponent(folderName(for: .now), isDirectory: true)
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

        try removeEarlierCopies(in: exportsRoot, keeping: directory)
        return Result(directory: directory, manifest: manifest)
    }

    /// Called only once the new copy is complete, so a failed export never leaves the
    /// user with no copy at all.
    private static func removeEarlierCopies(in exportsRoot: URL, keeping current: URL) throws {
        let entries = try FileManager.default.contentsOfDirectory(
            at: exportsRoot, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        )
        for entry in entries where entry.lastPathComponent != current.lastPathComponent {
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            try FileManager.default.removeItem(at: entry)
        }
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

    /// Band frames, one `BandRecordFile` per session, every frame in exactly one file.
    ///
    /// A session's frames are the ones in its `BleNormalizer.sessionWindows` window —
    /// the definition the normalizer decodes by, so the export and the derived data
    /// can't disagree about where a frame belongs. That matters most for a session the
    /// app never closed: it has no `ended_at`, and treating that as "until the end of
    /// time" once made every such session re-dump every later frame — 1.4 GB of files
    /// for 72 MB of band data. Where a boundary second sits in two windows, the later
    /// session takes it. Frames in no window go to `unassigned.bin`, so nothing that
    /// reached the inbox is left out.
    ///
    /// One pass in `seq` order, streamed to disk. Querying per session would scan the
    /// whole inbox each time — nothing indexes `received_at` — and building a file in
    /// memory doesn't survive a long session on a phone.
    private static func writeBleSessionBins(_ db: GRDB.Database, to directory: URL) throws -> Int {
        let windows = try BleNormalizer.sessionWindows(db)
        var files: [String: BandRecordFile] = [:]
        for window in windows {
            files[window.id] = try BandRecordFile(url: directory.appendingPathComponent("\(window.id).bin"))
        }

        let cursor = try Row.fetchCursor(
            db,
            sql: "SELECT kind, received_at, payload, codec FROM ingest_inbox WHERE source = 'ble' ORDER BY seq"
        )
        while let row = try cursor.next() {
            let receivedAt: Int64 = row["received_at"]
            let name = owner(of: receivedAt, in: windows) ?? unassignedFileName
            if files[name] == nil {
                files[name] = try BandRecordFile(url: directory.appendingPathComponent("\(name).bin"))
            }
            try files[name]?.append(kind: row["kind"], receivedAt: receivedAt, payload: IngestInbox.payload(for: row))
        }

        var totalBytes = 0
        for file in files.values {
            try file.close()
            totalBytes += file.byteCount
        }
        return totalBytes
    }

    static let unassignedFileName = "unassigned"

    /// The latest-starting window that contains `timestamp`. Sessions never overlap —
    /// one band connection at a time — so only that candidate needs checking.
    /// `windows` must be sorted by start, as `sessionWindows` returns them.
    static func owner(of timestamp: Int64, in windows: [BleNormalizer.SessionWindow]) -> String? {
        var low = 0, high = windows.count
        while low < high {
            let mid = (low + high) / 2
            if windows[mid].start <= timestamp { low = mid + 1 } else { high = mid }
        }
        guard low > 0 else { return nil }
        let candidate = windows[low - 1]
        return timestamp <= candidate.end ? candidate.id : nil
    }
}
