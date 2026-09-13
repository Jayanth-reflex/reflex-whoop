import SwiftUI
import GRDB

/// Row counts per table so Phase 1 storage work is visible and checkable without
/// waiting for the full Data screen (sync log, storage budget, raw inspector) in
/// later phases.
struct DataView: View {
    @Environment(AppContainer.self) private var container
    @State private var counts: [(table: String, count: Int)] = []
    @State private var isExporting = false
    @State private var lastExport: Exporter.Result?
    @State private var exportError: String?
    @State private var isReplaying = false
    @State private var replayResult: String?

    // `nonisolated` because `loadCounts` reads this from inside a database
    // closure that isn't main-actor-isolated. A constant list of table names
    // has no actor affinity; without this it is a Swift 6 concurrency error
    // rather than the warning it is today.
    nonisolated private static let tables = [
        "ingest_inbox", "cycles", "recoveries", "sleeps", "workouts",
        "ble_sessions", "ts_chunk", "dirty_days", "sync_log",
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if isExporting {
                        HStack {
                            ProgressView()
                            Text("Exporting…")
                        }
                    } else {
                        Button("Export data") { Task { await runExport() } }
                    }
                    if let lastExport {
                        let totalRows = lastExport.manifest.rowCounts.values.reduce(0, +)
                        let totalBytes = lastExport.manifest.byteCounts.values.reduce(0, +)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(totalRows) rows, \(ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            ShareLink("Share export", item: lastExport.directory)
                        }
                    }
                    if let exportError {
                        Text(exportError).font(.footnote).foregroundStyle(.red)
                    }
                } header: {
                    Text("Export")
                } footer: {
                    Text("Writes CSVs, a SQLite snapshot, and raw payloads to Documents/exports/ — reachable in Files → On My iPhone → ReflexWhoop and over the Finder cable, or share it directly above.")
                }

                Section {
                    if isReplaying {
                        HStack {
                            ProgressView()
                            Text("Re-deriving…")
                        }
                    } else {
                        Button("Re-derive BLE time series") { Task { await runReplay() } }
                    }
                    if let replayResult {
                        Text(replayResult).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("BLE")
                } footer: {
                    Text("Rebuilds every session's samples from the raw frames kept in the inbox. Safe to run any time — the bytes are the source of truth, and this only rewrites what was derived from them. Run it after a decoder improves.")
                }

                Section("Row counts") {
                    ForEach(counts, id: \.table) { row in
                        HStack {
                            Text(row.table)
                            Spacer()
                            Text("\(row.count)").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Data")
            .task { await loadCounts() }
            .refreshable { await loadCounts() }
        }
    }

    private func loadCounts() async {
        guard let loaded = try? await container.database.dbPool.read({ db in
            try Self.tables.map { table in
                (table, try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? 0)
            }
        }) else { return }
        counts = loaded
    }

    private func runExport() async {
        isExporting = true
        exportError = nil
        defer { isExporting = false }
        do {
            let documents = try FileManager.default.url(
                for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            )
            let exportsRoot = documents.appendingPathComponent("exports", isDirectory: true)
            lastExport = try await Exporter.export(dbPool: container.database.dbPool, exportsRoot: exportsRoot)
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func runReplay() async {
        isReplaying = true
        defer { isReplaying = false }
        do {
            let stats = try await container.replayBleNormalization()
            replayResult = "\(stats.sessionsProcessed) sessions · \(stats.samplesWritten) samples · \(stats.framesDecoded) frames decoded, \(stats.framesUnmapped) unmapped, \(stats.framesCorrupt) corrupt"
            await loadCounts()
        } catch {
            replayResult = error.localizedDescription
        }
    }
}
