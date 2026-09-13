import Foundation
import GRDB

enum RecordingQueries {
    /// Newest first. Sessions that captured nothing are kept: an empty
    /// recording is a fact about the band, not something to hide.
    static func recent(_ db: GRDB.Database, limit: Int?) throws -> [RecordingSummary] {
        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT b.id, b.started_at,
                   m.hr_mean, m.hr_min, m.hr_max, COALESCE(m.hr_sample_count, 0) AS reading_count,
                   r.first_minute, r.last_minute, COALESCE(r.minutes, 0) AS minutes
            FROM ble_sessions b
            LEFT JOIN session_metrics m ON m.session_id = b.id
            LEFT JOIN (
                SELECT session_id, MIN(minute_start) AS first_minute, MAX(minute_start) AS last_minute, COUNT(*) AS minutes
                FROM ts_rollup_minute WHERE channel = ? GROUP BY session_id
            ) r ON r.session_id = b.id
            ORDER BY b.started_at DESC
            LIMIT ?
            """,
            // SQLite treats a negative LIMIT as no limit.
            arguments: [BleNormalizer.Channel.heartRate, limit ?? -1]
        )
        return rows.map { row in
            RecordingSummary(
                id: row["id"],
                startedAt: date(fromSeconds: row["started_at"]),
                firstReadingAt: (row["first_minute"] as Int64?).map(date(fromSeconds:)),
                lastReadingAt: (row["last_minute"] as Int64?).map(date(fromSeconds:)),
                minutesWithReadings: row["minutes"],
                readingCount: row["reading_count"],
                averageBpm: row["hr_mean"],
                lowestBpm: row["hr_min"],
                highestBpm: row["hr_max"]
            )
        }
    }

    /// One-minute averages for a recording, oldest first.
    static func minuteReadings(_ db: GRDB.Database, sessionID: String) throws -> [HeartRateReading] {
        try Row.fetchAll(
            db,
            sql: """
            SELECT minute_start, mean_val FROM ts_rollup_minute
            WHERE channel = ? AND session_id = ? AND mean_val IS NOT NULL
            ORDER BY minute_start
            """,
            arguments: [BleNormalizer.Channel.heartRate, sessionID]
        ).map { row in
            HeartRateReading(time: date(fromSeconds: row["minute_start"]), bpm: row["mean_val"])
        }
    }

    /// Every recording's heart rate from `start` onwards, one reading per
    /// minute. Minutes covered by more than one session are merged, weighted
    /// by their raw reading counts.
    static func heartRate(_ db: GRDB.Database, since start: Date) throws -> HeartRateSpan {
        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT minute_start,
                   SUM(mean_val * sample_count) AS weighted_sum, SUM(sample_count) AS samples,
                   MIN(min_val) AS lowest, MAX(max_val) AS highest
            FROM ts_rollup_minute
            WHERE channel = ? AND minute_start >= ? AND mean_val IS NOT NULL AND sample_count > 0
            GROUP BY minute_start
            ORDER BY minute_start
            """,
            arguments: [BleNormalizer.Channel.heartRate, Int64(start.timeIntervalSince1970)]
        )
        let totalSamples = rows.reduce(0) { $0 + ($1["samples"] as Int64) }
        let weightedSum = rows.reduce(0) { $0 + ($1["weighted_sum"] as Double) }
        return HeartRateSpan(
            readings: rows.map { row in
                HeartRateReading(time: date(fromSeconds: row["minute_start"]), bpm: row["weighted_sum"] / Double(row["samples"] as Int64))
            },
            averageBpm: totalSamples > 0 ? weightedSum / Double(totalSamples) : nil,
            lowestBpm: rows.compactMap { $0["lowest"] as Double? }.min(),
            highestBpm: rows.compactMap { $0["highest"] as Double? }.max()
        )
    }

    private static func date(fromSeconds seconds: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(seconds))
    }
}
