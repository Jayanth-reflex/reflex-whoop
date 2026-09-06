import SwiftUI
import GRDB

/// Row counts per table so Phase 1 storage work is visible and checkable without
/// waiting for the full Data screen (sync log, storage budget, raw inspector) in
/// later phases.
struct DataView: View {
    @Environment(AppContainer.self) private var container
    @State private var counts: [(table: String, count: Int)] = []

    private static let tables = [
        "ingest_inbox", "cycles", "recoveries", "sleeps", "workouts",
        "ble_sessions", "ts_chunk", "dirty_days", "sync_log",
    ]

    var body: some View {
        NavigationStack {
            List(counts, id: \.table) { row in
                HStack {
                    Text(row.table)
                    Spacer()
                    Text("\(row.count)").foregroundStyle(.secondary)
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
}
