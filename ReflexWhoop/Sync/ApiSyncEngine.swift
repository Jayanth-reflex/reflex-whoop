import Foundation
import GRDB

/// Orchestrates the three sync modes described in docs/ARCHITECTURE.md's Source A
/// section: per-resource backfill (walks full history via cursor, checkpointed so
/// killing the app mid-backfill loses at most one page), incremental (7-day
/// re-scoring lookback, cheap thanks to `RecordDAO`'s content-hash skip), and
/// pending-score re-fetch (records WHOOP hadn't finished scoring yet).
///
/// `profile` and `body_measurement` are single-object resources with no
/// pagination or backfill concept — just a staleness-gated re-fetch.
struct ApiSyncEngine {
    struct Summary {
        var requestsMade = 0
        var recordsUpserted = 0
        var error: String?
    }

    let client: WhoopClient
    let dbPool: DatabasePool

    private let collectionResources: [(resource: String, kind: String, singleKind: String, fetchPage: (WhoopClient, String?, Date?, Date?) async throws -> Data)] = [
        ("cycle", ApiNormalizer.Kind.cyclePage, ApiNormalizer.Kind.cycleSingle, { client, token, start, end in try await client.cyclePage(nextToken: token, start: start, end: end) }),
        ("recovery", ApiNormalizer.Kind.recoveryPage, ApiNormalizer.Kind.recoverySingle, { client, token, start, end in try await client.recoveryPage(nextToken: token, start: start, end: end) }),
        ("sleep", ApiNormalizer.Kind.sleepPage, ApiNormalizer.Kind.sleepSingle, { client, token, start, end in try await client.sleepPage(nextToken: token, start: start, end: end) }),
        ("workout", ApiNormalizer.Kind.workoutPage, ApiNormalizer.Kind.workoutSingle, { client, token, start, end in try await client.workoutPage(nextToken: token, start: start, end: end) }),
    ]

    /// Runs one full sync pass: backfill anything not yet backfilled, incremental
    /// for anything stale per `SyncPolicy`, re-fetch anything still pending a
    /// score, then drain the inbox. Call from app-foreground (debounced), a
    /// manual "Sync now", or the `BGAppRefreshTask` handler.
    @discardableResult
    func syncNow(trigger: String) async throws -> Summary {
        var summary = Summary()
        let logID = try await beginSyncLog(trigger: trigger)

        do {
            for entry in collectionResources {
                if try await isBackfillComplete(entry.resource) {
                    if SyncPolicy.isStale(resource: entry.resource, lastSyncedAt: try await lastSyncedAt(entry.resource)) {
                        summary.requestsMade += try await incrementalSync(entry)
                    }
                } else {
                    summary.requestsMade += try await backfill(entry)
                }
            }

            summary.requestsMade += try await syncSingleObject(
                resource: "profile", kind: ApiNormalizer.Kind.profile, fetch: { try await client.profile() }
            )
            summary.requestsMade += try await syncSingleObject(
                resource: "body_measurement", kind: ApiNormalizer.Kind.bodyMeasurement, fetch: { try await client.bodyMeasurement() }
            )

            summary.requestsMade += try await refetchPendingScores()

            let normalizeStats = try ApiNormalizer.processPending(dbPool)
            summary.recordsUpserted = normalizeStats.upserted

            // Runs synchronously as part of the same sync: a sync that lands new
            // data but leaves daily_metrics/baselines/correlations stale would
            // show Today/Trends/Insights lagging one sync behind reality for no
            // reason a user could see or explain.
            try AnalysisEngine.run(dbPool)

            try await finishSyncLog(logID, requestsMade: summary.requestsMade, recordsUpserted: summary.recordsUpserted, error: nil)
        } catch {
            summary.error = error.localizedDescription
            try? await finishSyncLog(
                logID,
                requestsMade: summary.requestsMade,
                recordsUpserted: summary.recordsUpserted,
                error: error.localizedDescription,
                errorKind: SyncErrorKind.classify(error)
            )
            throw error
        }

        return summary
    }

    // MARK: - Backfill

    private func backfill(_ entry: (resource: String, kind: String, singleKind: String, fetchPage: (WhoopClient, String?, Date?, Date?) async throws -> Data)) async throws -> Int {
        var requests = 0
        var cursor = try await lastCursor(entry.resource)

        while true {
            let page = try await entry.fetchPage(client, cursor, nil, nil)
            requests += 1

            let nextToken = try Self.peekNextToken(page)
            try await dbPool.write { db in
                try IngestInbox.append(db, source: .api, kind: entry.kind, payload: page)
                try setCursor(db, resource: entry.resource, cursor: nextToken, backfillComplete: nextToken == nil)
            }

            cursor = nextToken
            if cursor == nil { break }
        }

        try await touchLastSyncedAt(entry.resource)
        return requests
    }

    // MARK: - Incremental (7-day re-scoring lookback)

    private func incrementalSync(_ entry: (resource: String, kind: String, singleKind: String, fetchPage: (WhoopClient, String?, Date?, Date?) async throws -> Data)) async throws -> Int {
        var requests = 0
        let start = Date().addingTimeInterval(-SyncPolicy.rescoreLookback)
        var cursor: String?

        while true {
            let page = try await entry.fetchPage(client, cursor, start, nil)
            requests += 1

            try await dbPool.write { db in
                try IngestInbox.append(db, source: .api, kind: entry.kind, payload: page)
            }

            cursor = try Self.peekNextToken(page)
            if cursor == nil { break }
        }

        try await touchLastSyncedAt(entry.resource)
        return requests
    }

    // MARK: - Single-object resources

    private func syncSingleObject(resource: String, kind: String, fetch: () async throws -> Data) async throws -> Int {
        guard SyncPolicy.isStale(resource: resource, lastSyncedAt: try await lastSyncedAt(resource)) else { return 0 }
        let payload = try await fetch()
        try await dbPool.write { db in
            try IngestInbox.append(db, source: .api, kind: kind, payload: payload)
        }
        try await touchLastSyncedAt(resource)
        return 1
    }

    // MARK: - Pending-score re-fetch

    private func refetchPendingScores() async throws -> Int {
        let pending = try await dbPool.read { db in
            try Row.fetchAll(db, sql: "SELECT resource, record_id, attempts FROM pending_scores WHERE attempts < 20")
        }

        var requests = 0
        for row in pending {
            let resource: String = row["resource"]
            let recordID: String = row["record_id"]

            let payload: Data
            let kind: String
            switch resource {
            case "cycle":
                payload = try await client.singleCycle(id: recordID)
                kind = ApiNormalizer.Kind.cycleSingle
            case "recovery":
                payload = try await client.singleRecovery(forCycleID: recordID)
                kind = ApiNormalizer.Kind.recoverySingle
            case "sleep":
                payload = try await client.singleSleep(id: recordID)
                kind = ApiNormalizer.Kind.sleepSingle
            case "workout":
                payload = try await client.singleWorkout(id: recordID)
                kind = ApiNormalizer.Kind.workoutSingle
            default:
                continue
            }
            requests += 1

            try await dbPool.write { db in
                try IngestInbox.append(db, source: .api, kind: kind, payload: payload)
                try db.execute(
                    sql: "UPDATE pending_scores SET attempts = attempts + 1 WHERE resource = ? AND record_id = ?",
                    arguments: [resource, recordID]
                )
            }
        }
        return requests
    }

    // MARK: - sync_state / sync_log helpers

    private func lastCursor(_ resource: String) async throws -> String? {
        try await dbPool.read { db in
            try String.fetchOne(db, sql: "SELECT last_cursor FROM sync_state WHERE resource = ?", arguments: [resource])
        }
    }

    private func isBackfillComplete(_ resource: String) async throws -> Bool {
        try await dbPool.read { db in
            try Bool.fetchOne(db, sql: "SELECT backfill_complete FROM sync_state WHERE resource = ?", arguments: [resource]) ?? false
        }
    }

    private func lastSyncedAt(_ resource: String) async throws -> Date? {
        try await dbPool.read { db in
            guard let seconds = try Int64.fetchOne(db, sql: "SELECT last_synced_at FROM sync_state WHERE resource = ?", arguments: [resource]) else {
                return nil
            }
            return Date(timeIntervalSince1970: Double(seconds))
        }
    }

    private func setCursor(_ db: GRDB.Database, resource: String, cursor: String?, backfillComplete: Bool) throws {
        try db.execute(
            sql: """
            INSERT INTO sync_state (resource, last_cursor, backfill_complete, last_synced_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(resource) DO UPDATE SET
                last_cursor = excluded.last_cursor, backfill_complete = excluded.backfill_complete,
                last_synced_at = excluded.last_synced_at
            """,
            arguments: [resource, cursor, backfillComplete, Int64(Date().timeIntervalSince1970)]
        )
    }

    private func touchLastSyncedAt(_ resource: String) async throws {
        try await dbPool.write { db in
            try db.execute(
                sql: """
                INSERT INTO sync_state (resource, last_synced_at, backfill_complete)
                VALUES (?, ?, COALESCE((SELECT backfill_complete FROM sync_state WHERE resource = ?), 0))
                ON CONFLICT(resource) DO UPDATE SET last_synced_at = excluded.last_synced_at
                """,
                arguments: [resource, Int64(Date().timeIntervalSince1970), resource]
            )
        }
    }

    private func beginSyncLog(trigger: String) async throws -> Int64 {
        try await dbPool.write { db in
            try db.execute(
                sql: "INSERT INTO sync_log (started_at, trigger) VALUES (?, ?)",
                arguments: [Int64(Date().timeIntervalSince1970), trigger]
            )
            return db.lastInsertedRowID
        }
    }

    private func finishSyncLog(_ id: Int64, requestsMade: Int, recordsUpserted: Int, error: String?, errorKind: SyncErrorKind? = nil) async throws {
        try await dbPool.write { db in
            try db.execute(
                sql: "UPDATE sync_log SET finished_at = ?, requests_made = ?, records_upserted = ?, error = ?, error_kind = ? WHERE id = ?",
                arguments: [Int64(Date().timeIntervalSince1970), requestsMade, recordsUpserted, error, errorKind?.rawValue, id]
            )
        }
    }

    /// Peeks only `next_token` from a raw collection page — deliberately not a
    /// full model decode. Full decoding stays the normalizer's job, run only
    /// after the raw bytes are safely in the inbox; this is protocol-level
    /// pagination metadata, not business data.
    private static func peekNextToken(_ payload: Data) throws -> String? {
        struct Peek: Decodable {
            let nextToken: String?
            enum CodingKeys: String, CodingKey { case nextToken = "next_token" }
        }
        return try JSONDecoder().decode(Peek.self, from: payload).nextToken
    }
}
