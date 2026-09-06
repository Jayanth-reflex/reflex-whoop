import Foundation
import GRDB

/// Owns the single SQLite connection pool for the app. There must be exactly one
/// `Database` instance alive at a time — GRDB's `DatabasePool` already serializes
/// writers internally, but we additionally route every write through this type so
/// call sites can't accidentally open a second connection to the same file.
final class Database: Sendable {
    let dbPool: DatabasePool

    init(path: String) throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        config.prepareDatabase { db in
            // These are per-connection settings, safe on every connection `DatabasePool`
            // opens — including its read-only reader connections. `auto_vacuum` is not:
            // it rewrites the database header and fails with "attempt to write a
            // readonly database" on a reader, so it's set once below via `dbPool.write`
            // instead of here.
            //
            // NORMAL is safe under WAL (only risks losing the last transaction on a
            // hard power loss, never corruption) and is materially faster than FULL
            // for the write volume BLE sessions generate.
            try db.execute(sql: "PRAGMA synchronous = NORMAL")
            try db.execute(sql: "PRAGMA temp_store = MEMORY")
            try db.execute(sql: "PRAGMA mmap_size = 268435456") // 256 MB
        }

        dbPool = try DatabasePool(path: path, configuration: config)
        try dbPool.write { db in
            try db.execute(sql: "PRAGMA auto_vacuum = INCREMENTAL")
        }
        try Migrator.makeMigrator().migrate(dbPool)
    }

    /// The default on-device location: `Documents/reflexwhoop.sqlite`. Documents is
    /// deliberately used (not Application Support) because `UIFileSharingEnabled` +
    /// `LSSupportsOpeningDocumentsInPlace` exposes this folder in Files and Finder,
    /// which is the export path a free-tier Apple ID leaves us.
    static func defaultPath() throws -> String {
        let documents = try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return documents.appendingPathComponent("reflexwhoop.sqlite").path
    }

    /// Periodic maintenance — call from a background task, not on every launch.
    /// Incremental vacuum matters here because BLE chunk blobs churn: sessions get
    /// re-encoded, old chunks deleted, and without periodic reclaiming the file only grows.
    func runMaintenance() async throws {
        try await dbPool.write { db in
            try db.execute(sql: "PRAGMA incremental_vacuum")
            try db.execute(sql: "ANALYZE")
        }
    }
}
