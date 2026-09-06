import Foundation
import GRDB

/// Drains `ingest_inbox` rows written by the API sync engine and turns them into
/// normalized rows via `RecordDAO`. Runs as a distinct pass *after* ingestion so a
/// decoding bug never loses data — see `IngestInbox`'s doc comment.
///
/// `kind` on each inbox row is one of a small fixed set of endpoint-path conventions
/// the sync engine uses when it writes to the inbox. Collection endpoints (no id in
/// the path) are stored as the raw `PaginatedResponse<T>` envelope; single-record
/// endpoints (fetched by id, e.g. for a `pending_scores` re-fetch) are stored as the
/// bare decoded object with a "/single" suffix on the kind.
enum ApiNormalizer {
    /// Bump this whenever a decode/upsert bug is fixed. Existing inbox rows are never
    /// automatically replayed on a version bump — call `replay(db:)` explicitly when
    /// that's actually wanted, since replaying is a deliberate, potentially expensive
    /// operation (it rewrites `dirty_days` for everything it touches).
    static let decoderVersion = 1

    enum Kind {
        static let cyclePage = "/v2/cycle"
        static let cycleSingle = "/v2/cycle/single"
        static let recoveryPage = "/v2/recovery"
        static let recoverySingle = "/v2/cycle/single/recovery"
        static let sleepPage = "/v2/activity/sleep"
        static let sleepSingle = "/v2/activity/sleep/single"
        static let workoutPage = "/v2/activity/workout"
        static let workoutSingle = "/v2/activity/workout/single"
        static let profile = "/v2/user/profile/basic"
        static let bodyMeasurement = "/v2/user/measurement/body"
    }

    struct Stats {
        var processed = 0
        var upserted = 0
        var skippedUnchanged = 0
        var deferred = 0
        var failed = 0
    }

    /// Processes every undecoded API inbox row, in a single write transaction per
    /// batch so a crash mid-drain leaves either "fully processed" or "not yet
    /// touched" rows, never a half-applied batch.
    @discardableResult
    static func processPending(_ dbPool: DatabasePool) throws -> Stats {
        var stats = Stats()
        try dbPool.write { db in
            // A single sweep processes undecoded rows in seq (arrival) order, which
            // is usually also dependency order — but not always: e.g. a body
            // measurement can be inbox-appended before the profile row that supplies
            // its user id, in the same batch. Re-sweeping while a sweep still makes
            // progress lets a later row's write unblock an earlier row's deferral
            // within the same call, rather than only on the *next* sync's call.
            // Bounded to guard against a genuine cycle rather than looping forever.
            var seenSeqs = Set<Int64>()
            var deferredThisRound = 0
            for _ in 0..<5 {
                let rows = try IngestInbox.fetchUndecoded(db, source: .api)
                if rows.isEmpty { break }

                var progressed = false
                deferredThisRound = 0

                for row in rows {
                    let seq: Int64 = row["seq"]
                    if seenSeqs.insert(seq).inserted {
                        stats.processed += 1
                    }
                    let kind: String = row["kind"]
                    let payload = IngestInbox.payload(for: row)

                    do {
                        let result = try decodeAndUpsert(db, kind: kind, payload: payload, inboxSeq: seq)
                        switch result {
                        case .upserted: stats.upserted += 1; progressed = true
                        case .unchanged: stats.skippedUnchanged += 1; progressed = true
                        case .deferred: deferredThisRound += 1
                        }
                        if result != .deferred {
                            try IngestInbox.markDecoded(db, seq: seq, decoderVersion: decoderVersion)
                        }
                    } catch {
                        // Leave undecoded for a future pass rather than losing the row;
                        // the inbox is the source of truth precisely so this is safe.
                        stats.failed += 1
                        progressed = true // don't retry a hard decode failure in a tight loop
                    }
                }

                if deferredThisRound == 0 || !progressed { break }
            }
            stats.deferred = deferredThisRound
        }
        return stats
    }

    private enum DecodeResult: Equatable {
        case upserted
        case unchanged
        case deferred // body measurement arrived before profile; wait for a userId
    }

    private static func decodeAndUpsert(_ db: GRDB.Database, kind: String, payload: Data, inboxSeq: Int64) throws -> DecodeResult {
        let decoder = JSONDecoder()

        switch kind {
        case Kind.cyclePage:
            let page = try decoder.decode(PaginatedResponse<Cycle>.self, from: payload)
            var any = false
            for cycle in page.records { any = try RecordDAO.upsert(db, cycle: cycle, inboxSeq: inboxSeq) || any }
            return any ? .upserted : .unchanged

        case Kind.cycleSingle:
            let cycle = try decoder.decode(Cycle.self, from: payload)
            return try RecordDAO.upsert(db, cycle: cycle, inboxSeq: inboxSeq) ? .upserted : .unchanged

        case Kind.recoveryPage:
            let page = try decoder.decode(PaginatedResponse<Recovery>.self, from: payload)
            var any = false
            for recovery in page.records { any = try RecordDAO.upsert(db, recovery: recovery, inboxSeq: inboxSeq) || any }
            return any ? .upserted : .unchanged

        case Kind.recoverySingle:
            let recovery = try decoder.decode(Recovery.self, from: payload)
            return try RecordDAO.upsert(db, recovery: recovery, inboxSeq: inboxSeq) ? .upserted : .unchanged

        case Kind.sleepPage:
            let page = try decoder.decode(PaginatedResponse<Sleep>.self, from: payload)
            var any = false
            for sleep in page.records { any = try RecordDAO.upsert(db, sleep: sleep, inboxSeq: inboxSeq) || any }
            return any ? .upserted : .unchanged

        case Kind.sleepSingle:
            let sleep = try decoder.decode(Sleep.self, from: payload)
            return try RecordDAO.upsert(db, sleep: sleep, inboxSeq: inboxSeq) ? .upserted : .unchanged

        case Kind.workoutPage:
            let page = try decoder.decode(PaginatedResponse<Workout>.self, from: payload)
            var any = false
            for workout in page.records { any = try RecordDAO.upsert(db, workout: workout, inboxSeq: inboxSeq) || any }
            return any ? .upserted : .unchanged

        case Kind.workoutSingle:
            let workout = try decoder.decode(Workout.self, from: payload)
            return try RecordDAO.upsert(db, workout: workout, inboxSeq: inboxSeq) ? .upserted : .unchanged

        case Kind.profile:
            let profile = try decoder.decode(Profile.self, from: payload)
            try RecordDAO.upsert(db, profile: profile)
            return .upserted

        case Kind.bodyMeasurement:
            let measurement = try decoder.decode(BodyMeasurement.self, from: payload)
            guard let userId = try Int64.fetchOne(db, sql: "SELECT user_id FROM profile LIMIT 1") else {
                return .deferred // wait until the profile sync has landed
            }
            try RecordDAO.upsert(db, bodyMeasurement: measurement, userId: userId)
            return .upserted

        default:
            throw NormalizerError.unknownKind(kind)
        }
    }

    enum NormalizerError: Error {
        case unknownKind(String)
    }
}
