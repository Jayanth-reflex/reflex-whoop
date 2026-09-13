import SwiftUI
import GRDB

/// What's stored, and how to get it off the phone.
///
/// Framed around what a person owns rather than how the store is built: how
/// much history is here, how to take a copy, and how to rebuild the readings
/// from the raw recordings. The per-table breakdown is available but folded
/// away — table names are implementation, not something anyone manages.
struct DataView: View {
    @Environment(AppContainer.self) private var container
    @State private var counts: [(table: String, count: Int)] = []
    @State private var archive: ArchiveSummary?
    @State private var isExporting = false
    @State private var lastExport: Exporter.Result?
    @State private var exportError: String?
    @State private var isRebuilding = false
    @State private var rebuildResult: String?
    @State private var showTableCounts = false

    // `nonisolated` because `loadCounts` reads this from inside a database
    // closure that isn't main-actor-isolated. A constant list of table names
    // has no actor affinity; without this it is a Swift 6 concurrency error
    // rather than the warning it is today.
    nonisolated private static let tables = [
        "ingest_inbox", "cycles", "recoveries", "sleeps", "workouts",
        "daily_metrics", "baselines", "correlations", "anomalies",
        "ble_sessions", "ts_chunk", "session_metrics",
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ink.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.gutter) {
                        if let archive { summary(archive) }
                        exportCard
                        rebuildCard
                        tableCountsCard
                    }
                    .padding(Theme.gutter)
                }
            }
            .navigationTitle("Data")
            .toolbarBackground(Theme.ink, for: .navigationBar)
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func summary(_ archive: ArchiveSummary) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                Eyebrow("On this phone", tint: Theme.vital)
                HStack(spacing: 28) {
                    Readout(label: "Days", value: "\(archive.dayCount)", size: 26)
                    Readout(label: "Sessions", value: "\(archive.bleSessionCount)", size: 26)
                    Readout(label: "Readings", value: compact(archive.bleSampleCount), size: 26)
                }
                if let first = archive.firstDay, let last = archive.lastDay {
                    Text("\(first) to \(last)")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
            }
        }
    }

    private var exportCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow("Take a copy")
                Text("Writes everything to spreadsheets and a database file you can open on a computer.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                if isExporting {
                    HStack(spacing: 8) {
                        ProgressView().tint(Theme.muted)
                        Text("Exporting…").font(.subheadline).foregroundStyle(Theme.muted)
                    }
                } else {
                    Button("Export") { Task { await runExport() } }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.vital)
                        .foregroundStyle(Theme.ink)
                }

                if let lastExport {
                    let rows = lastExport.manifest.rowCounts.values.reduce(0, +)
                    let bytes = lastExport.manifest.byteCounts.values.reduce(0, +)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(rows) rows · \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.muted)
                        ShareLink("Share", item: lastExport.directory)
                            .font(.subheadline)
                    }
                }
                if let exportError {
                    Text(exportError).font(.caption).foregroundStyle(Theme.alert)
                }
                Text("Also in Files, under On My iPhone → ReflexWhoop.")
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    private var rebuildCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow("Rebuild readings")
                Text("Recreates heart rate history from the raw band recordings. Safe to run any time — the originals are never changed.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if isRebuilding {
                    HStack(spacing: 8) {
                        ProgressView().tint(Theme.muted)
                        Text("Rebuilding…").font(.subheadline).foregroundStyle(Theme.muted)
                    }
                } else {
                    Button("Rebuild") { Task { await runRebuild() } }
                        .buttonStyle(.bordered)
                        .tint(Theme.muted)
                }
                if let rebuildResult {
                    Text(rebuildResult).font(.caption).foregroundStyle(Theme.muted)
                }
            }
        }
    }

    private var tableCountsCard: some View {
        Card {
            DisclosureGroup(isExpanded: $showTableCounts) {
                VStack(spacing: 6) {
                    ForEach(counts, id: \.table) { row in
                        HStack {
                            Text(row.table)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(Theme.muted)
                            Spacer()
                            Text("\(row.count)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Theme.text)
                        }
                    }
                }
                .padding(.top, 10)
            } label: {
                Eyebrow("Storage detail")
            }
            .tint(Theme.muted)
        }
    }

    private func compact(_ value: Int) -> String {
        value >= 1000 ? String(format: "%.1fk", Double(value) / 1000) : "\(value)"
    }

    private func load() async {
        archive = try? await container.database.dbPool.read { try SourceStatus.archive($0) }
        if let loaded = try? await container.database.dbPool.read({ db in
            try Self.tables.map { ($0, try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \($0)") ?? 0) }
        }) {
            counts = loaded
        }
    }

    private func runExport() async {
        isExporting = true
        exportError = nil
        defer { isExporting = false }
        do {
            let documents = try FileManager.default.url(
                for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            )
            lastExport = try await Exporter.export(
                dbPool: container.database.dbPool,
                exportsRoot: documents.appendingPathComponent("exports", isDirectory: true)
            )
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func runRebuild() async {
        isRebuilding = true
        defer { isRebuilding = false }
        do {
            let stats = try await container.replayBleNormalization()
            rebuildResult = "\(stats.sessionsProcessed) sessions · \(stats.samplesWritten) readings"
            await load()
        } catch {
            rebuildResult = error.localizedDescription
        }
    }
}
