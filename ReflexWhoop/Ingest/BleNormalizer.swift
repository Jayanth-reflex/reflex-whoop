import Foundation
import GRDB

/// Drains `ingest_inbox` rows written by `SpikeRecorder` and turns them into
/// queryable time-series rows — the second half of the BLE pipeline, which
/// `docs/ADR-001-data-sovereignty.md` (S2) found had never been built: raw
/// frames landed in the inbox and nothing downstream ever read them, so not one
/// BLE datum was queryable by the app, the Trends screen, or the MCP server.
///
/// Mirrors `ApiNormalizer`'s contract: a separate pass after ingestion, so a
/// decoder bug is never data loss. The inbox keeps the bytes; `replay` re-derives
/// everything from them whenever a decoder improves.
///
/// **Only confirmed decodes emit rows.** Today that is realtime heart rate
/// (`0x28`, `RealtimeHRDecoder`). Frames whose packet type has no confirmed
/// decoder are counted as `unmapped` and otherwise ignored — never guessed at,
/// per docs/PROTOCOL-GEN5.md's "only decode a field once captured frames confirm it."
/// Those counts are the point of `session_metrics.unmapped_frame_count`: they
/// are how firmware drift announces itself (S6).
enum BleNormalizer {
    /// Bump when a decoder changes what bytes mean. Existing rows are not
    /// replayed automatically — call `replay` deliberately.
    static let decoderVersion = 1
    static let algoVersion = 1

    /// Channel names are the neutral contract: a source-agnostic label, not a
    /// WHOOP packet type. A future sensor emitting heart rate writes `"hr"` too.
    enum Channel {
        static let heartRate = "hr"
    }

    struct Stats: Equatable {
        var sessionsProcessed = 0
        var framesDecoded = 0
        var framesUnmapped = 0
        var framesCorrupt = 0
        var samplesWritten = 0
        var orphanRows = 0
    }

    /// Normalizes every session that has at least one undecoded inbox row.
    ///
    /// Works a whole session at a time rather than a fixed row batch, and
    /// re-reads that session's already-decoded rows too. That costs a little
    /// redundant work and buys exact idempotency: `ChunkStore` overwrites a
    /// bucket wholesale rather than merging into it, so a session split across
    /// two partial passes would otherwise lose the earlier pass's samples from
    /// any bucket both passes touched.
    @discardableResult
    static func processPending(_ dbPool: DatabasePool) throws -> Stats {
        var stats = Stats()
        try dbPool.write { db in
            let windows = try sessionWindows(db)

            for window in windows {
                guard try hasUndecodedRows(db, window: window) else { continue }
                let sessionStats = try normalize(db, window: window)
                stats.sessionsProcessed += 1
                stats.framesDecoded += sessionStats.framesDecoded
                stats.framesUnmapped += sessionStats.framesUnmapped
                stats.framesCorrupt += sessionStats.framesCorrupt
                stats.samplesWritten += sessionStats.samplesWritten
            }

            // Frames that fall inside no session's window — received before the
            // first session row existed, or after one was closed. Marked decoded
            // so they don't re-scan forever; the bytes stay in the inbox.
            stats.orphanRows = try markOrphansDecoded(db, windows: windows)
        }
        return stats
    }

    /// Clears the decoded marks and the derived rows for every BLE session, so
    /// the next `processPending` re-derives everything from the inbox bytes.
    /// Deliberately explicit — this is the operation that makes a decoder fix
    /// retroactive, and it rewrites every chunk it touches.
    @discardableResult
    static func replay(_ dbPool: DatabasePool) throws -> Stats {
        try dbPool.write { db in
            try db.execute(sql: "DELETE FROM session_metrics")
            try db.execute(sql: "DELETE FROM ts_chunk")
            try db.execute(sql: "DELETE FROM ts_rollup_minute")
            try db.execute(
                sql: "UPDATE ingest_inbox SET decoded_at = NULL, decoder_version = NULL WHERE source = ?",
                arguments: [IngestInbox.Source.ble.rawValue]
            )
        }
        return try processPending(dbPool)
    }

    // MARK: - Session windows

    /// A session's frames are the inbox rows whose `received_at` falls in its
    /// window. Inbox rows carry no session id — `SpikeRecorder` writes them on
    /// the BLE callback path, where the cheapest possible write is the right
    /// call — so the association is reconstructed by time here. Sessions never
    /// overlap (one `BandConnection` at a time), which is what makes this sound.
    struct SessionWindow {
        let id: String
        let start: Int64
        /// Exclusive upper bound: the session's own `ended_at` when it was
        /// closed cleanly, otherwise the next session's start (a session that
        /// was never closed — app killed mid-session — owns everything up to
        /// the next one).
        let end: Int64
    }

    static func sessionWindows(_ db: GRDB.Database) throws -> [SessionWindow] {
        let rows = try Row.fetchAll(
            db,
            sql: "SELECT id, started_at, ended_at FROM ble_sessions ORDER BY started_at ASC"
        )
        return rows.enumerated().map { index, row in
            let start: Int64 = row["started_at"]
            let explicitEnd: Int64? = row["ended_at"]
            let nextStart: Int64? = index + 1 < rows.count ? rows[index + 1]["started_at"] : nil
            let end = explicitEnd ?? nextStart ?? Int64.max
            return SessionWindow(id: row["id"], start: start, end: max(end, start))
        }
    }

    // Both undecoded queries name their index. The inbox is hundreds of thousands of
    // BLE rows with a handful undecoded, and SQLite, holding no statistics, answers
    // `source = ?` from `idx_inbox_source_kind` instead — a walk of nearly the whole
    // table. `hasUndecodedRows` runs once per session inside `processPending`'s write
    // transaction, so on the phone that held the write lock and a full core for ~50 s
    // until iOS killed the app for CPU use.
    //
    // `INDEXED BY` rather than a planner hint because a silent fallback is the thing
    // to rule out: if the index is ever renamed or dropped, these statements fail to
    // prepare and the tests say so, instead of the app quietly walking the table again.

    static let undecodedInWindowSQL = """
        SELECT COUNT(*) FROM ingest_inbox INDEXED BY idx_inbox_undecoded
        WHERE source = ? AND decoded_at IS NULL AND received_at >= ? AND received_at <= ?
        """

    static let undecodedSQL = """
        SELECT seq, received_at FROM ingest_inbox INDEXED BY idx_inbox_undecoded
        WHERE source = ? AND decoded_at IS NULL
        """

    private static func hasUndecodedRows(_ db: GRDB.Database, window: SessionWindow) throws -> Bool {
        try Int.fetchOne(
            db,
            sql: undecodedInWindowSQL,
            arguments: [IngestInbox.Source.ble.rawValue, window.start, window.end]
        ) ?? 0 > 0
    }

    private static func markOrphansDecoded(_ db: GRDB.Database, windows: [SessionWindow]) throws -> Int {
        let rows = try Row.fetchAll(
            db,
            sql: undecodedSQL,
            arguments: [IngestInbox.Source.ble.rawValue]
        )
        var count = 0
        for row in rows {
            let receivedAt: Int64 = row["received_at"]
            let belongsToSession = windows.contains { receivedAt >= $0.start && receivedAt <= $0.end }
            guard !belongsToSession else { continue }
            try IngestInbox.markDecoded(db, seq: row["seq"], decoderVersion: decoderVersion)
            count += 1
        }
        return count
    }

    // MARK: - Per-session normalization

    private static func normalize(_ db: GRDB.Database, window: SessionWindow) throws -> Stats {
        var stats = Stats()
        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT seq, kind, received_at, payload, codec FROM ingest_inbox
            WHERE source = ? AND received_at >= ? AND received_at <= ?
            ORDER BY seq ASC
            """,
            arguments: [IngestInbox.Source.ble.rawValue, window.start, window.end]
        )
        guard !rows.isEmpty else { return stats }

        let reassembler = FrameReassembler()
        var heartRate: [Sample] = []
        var seqs: [Int64] = []

        for row in rows {
            seqs.append(row["seq"])
            let kind: String = row["kind"]
            // fd4b0007 carries CBOR device metadata, not envelope-framed sensor
            // data (docs/PROTOCOL-GEN5.md). Feeding it to the reassembler would
            // corrupt the buffer with bytes that were never a frame.
            guard kind != Ble.unknown0007CharacteristicUUID.uuidString else { continue }

            let receivedAt: Int64 = row["received_at"]
            for frame in reassembler.feed(IngestInbox.payload(for: row)) {
                guard frame.headerCrcValid, frame.trailerCrcValid else {
                    stats.framesCorrupt += 1
                    continue
                }
                if let bpm = RealtimeHRDecoder.heartRateBpm(inner: frame.inner) {
                    heartRate.append(Sample(timestamp: receivedAt, value: Int64(bpm)))
                    stats.framesDecoded += 1
                } else {
                    stats.framesUnmapped += 1
                }
            }
        }

        // Full rewrite rather than merge: this pass re-read the session's entire
        // history, so what it computed is the complete truth for that session.
        try db.execute(sql: "DELETE FROM ts_chunk WHERE session_id = ?", arguments: [window.id])
        try db.execute(sql: "DELETE FROM ts_rollup_minute WHERE session_id = ?", arguments: [window.id])

        if !heartRate.isEmpty {
            try ChunkStore.write(
                db,
                channel: Channel.heartRate,
                sessionID: window.id,
                samples: heartRate.sorted { $0.timestamp < $1.timestamp },
                nominalHz: 1.0
            )
            stats.samplesWritten += heartRate.count
        }

        try writeSessionMetrics(db, sessionID: window.id, heartRate: heartRate, stats: stats)

        for seq in seqs {
            try IngestInbox.markDecoded(db, seq: seq, decoderVersion: decoderVersion)
        }
        return stats
    }

    /// Writes what this session can actually report. The HRV columns
    /// (`rmssd_milli`, `sdnn_milli`, `pnn50_pct`, `dfa_alpha1`) are left NULL on
    /// purpose: every one of them needs beat-to-beat RR intervals, and no
    /// confirmed Gen 5 decoder produces those yet. `signal_quality` carries the
    /// reason rather than leaving a caller to guess at an unexplained void —
    /// docs/ARCHITECTURE.md: "absent input yields unavailable, not zero."
    private static func writeSessionMetrics(
        _ db: GRDB.Database,
        sessionID: String,
        heartRate: [Sample],
        stats: Stats
    ) throws {
        let values = heartRate.map(\.value)
        let mean = values.isEmpty ? nil : Double(values.reduce(0, +)) / Double(values.count)
        let totalFrames = stats.framesDecoded + stats.framesUnmapped + stats.framesCorrupt
        // Share of CRC-valid frames we could actually turn into a sample. This
        // is the drift canary: a firmware change that moves or renames the
        // realtime record makes this collapse toward zero while frames keep
        // arriving.
        let signalQuality = totalFrames == 0 ? nil : Double(stats.framesDecoded) / Double(totalFrames)

        try db.execute(
            sql: """
            INSERT INTO session_metrics
                (session_id, rmssd_milli, sdnn_milli, pnn50_pct, dfa_alpha1,
                 rr_artifact_rejection_pct, respiratory_rate, signal_quality,
                 hr_mean, hr_min, hr_max, hr_sample_count,
                 decoded_frame_count, unmapped_frame_count, corrupt_frame_count,
                 algo_version, computed_at)
            VALUES (?, NULL, NULL, NULL, NULL, NULL, NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(session_id) DO UPDATE SET
                signal_quality = excluded.signal_quality,
                hr_mean = excluded.hr_mean,
                hr_min = excluded.hr_min,
                hr_max = excluded.hr_max,
                hr_sample_count = excluded.hr_sample_count,
                decoded_frame_count = excluded.decoded_frame_count,
                unmapped_frame_count = excluded.unmapped_frame_count,
                corrupt_frame_count = excluded.corrupt_frame_count,
                algo_version = excluded.algo_version,
                computed_at = excluded.computed_at
            """,
            arguments: [
                sessionID, signalQuality,
                mean, values.min(), values.max(), values.count,
                stats.framesDecoded, stats.framesUnmapped, stats.framesCorrupt,
                algoVersion, Int64(Date().timeIntervalSince1970),
            ]
        )
    }
}
