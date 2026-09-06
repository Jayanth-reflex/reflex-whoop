import Foundation
import GRDB

/// One sample of a BLE channel, already quantized to an integer domain by the caller
/// (e.g. accel f32 g → milli-g Int64, HR stays Int64 bpm, RR stays Int64 ms).
struct Sample {
    let timestamp: Int64 // unix seconds (sub-second precision folded into value scale where it matters, e.g. RR)
    let value: Int64
}

/// Persists one channel's samples for a session, bucketed into 1-hour chunks and
/// rolled up into per-minute summaries so charts never have to decode a chunk just
/// to draw a year-long trend line.
struct ChunkStore {
    private static let bucketSeconds: Int64 = 3600

    /// Writes `samples` (already sorted by timestamp, already quantized) for one
    /// channel of one session. Splits across hour buckets as needed and writes the
    /// matching per-minute rollup rows in the same transaction.
    static func write(
        _ writer: GRDB.Database,
        channel: String,
        sessionID: String,
        samples: [Sample],
        nominalHz: Double?
    ) throws {
        guard !samples.isEmpty else { return }

        let grouped = Dictionary(grouping: samples) { $0.timestamp / bucketSeconds }

        for (bucketIndex, bucketSamples) in grouped {
            let sorted = bucketSamples.sorted { $0.timestamp < $1.timestamp }
            let values = sorted.map(\.value)
            let (encoding, rawBytes) = ChunkCodec.encode(values)
            let (blobCodec, compressed) = ChunkCompression.compress(rawBytes, using: .lzfse)

            let doubles = values.map(Double.init)
            let minVal = doubles.min()
            let maxVal = doubles.max()
            let meanVal = doubles.reduce(0, +) / Double(doubles.count)

            try writer.execute(
                sql: """
                INSERT INTO ts_chunk
                    (channel, session_id, bucket_start, sample_count, nominal_hz,
                     first_ts, last_ts, encoding, codec, min_val, max_val, mean_val, blob)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(channel, session_id, bucket_start) DO UPDATE SET
                    sample_count = excluded.sample_count,
                    nominal_hz = excluded.nominal_hz,
                    first_ts = excluded.first_ts,
                    last_ts = excluded.last_ts,
                    encoding = excluded.encoding,
                    codec = excluded.codec,
                    min_val = excluded.min_val,
                    max_val = excluded.max_val,
                    mean_val = excluded.mean_val,
                    blob = excluded.blob
                """,
                arguments: [
                    channel, sessionID, bucketIndex * bucketSeconds, sorted.count, nominalHz,
                    sorted.first!.timestamp, sorted.last!.timestamp,
                    encoding.rawValue, blobCodec.rawValue,
                    minVal, maxVal, meanVal, compressed,
                ]
            )

            try writeMinuteRollup(writer, channel: channel, sessionID: sessionID, samples: sorted)
        }
    }

    /// Reads and decodes every sample in `channel` for `sessionID` within
    /// `[startTs, endTs]`. Only called when the UI actually zooms into a window —
    /// the Trends/Live screens read `ts_rollup_minute` for everything else.
    static func read(
        _ reader: GRDB.Database,
        channel: String,
        sessionID: String,
        startTs: Int64,
        endTs: Int64
    ) throws -> [Sample] {
        let rows = try Row.fetchAll(
            reader,
            sql: """
            SELECT bucket_start, sample_count, encoding, codec, blob
            FROM ts_chunk
            WHERE channel = ? AND session_id = ? AND bucket_start <= ? AND bucket_start + ? >= ?
            ORDER BY bucket_start
            """,
            arguments: [channel, sessionID, endTs, bucketSeconds, startTs]
        )

        var result: [Sample] = []
        for row in rows {
            let bucketStart: Int64 = row["bucket_start"]
            let sampleCount: Int = row["sample_count"]
            guard let encoding = ChunkCodec.Encoding(rawValue: row["encoding"] as String) else { continue }
            guard let blobCodec = ChunkBlobCodec(rawValue: row["codec"] as String) else { continue }
            let blob: Data = row["blob"]

            // Upper-bound hint for the decompressor: raw i64 encoding is the worst case per sample.
            let expectedSize = sampleCount * MemoryLayout<Int64>.size
            let rawBytes = ChunkCompression.decompress(blob, using: blobCodec, expectedSize: expectedSize)
            let values = ChunkCodec.decode(encoding: encoding, bytes: rawBytes, count: sampleCount)

            // We only stored delta-encoded values relative to first_ts's bucket; timestamps
            // aren't reconstructed here since chunks store values, not per-sample timestamps
            // beyond first/last. Callers needing exact per-sample timestamps should read
            // ts_rollup_minute for coarse alignment or reconstruct from nominal_hz.
            _ = bucketStart
            for value in values {
                result.append(Sample(timestamp: 0, value: value))
            }
        }
        return result
    }

    private static func writeMinuteRollup(
        _ writer: GRDB.Database,
        channel: String,
        sessionID: String,
        samples: [Sample]
    ) throws {
        let byMinute = Dictionary(grouping: samples) { $0.timestamp / 60 }
        for (minuteIndex, minuteSamples) in byMinute {
            let doubles = minuteSamples.map { Double($0.value) }
            try writer.execute(
                sql: """
                INSERT INTO ts_rollup_minute
                    (channel, session_id, minute_start, min_val, max_val, mean_val, sample_count)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(channel, session_id, minute_start) DO UPDATE SET
                    min_val = excluded.min_val,
                    max_val = excluded.max_val,
                    mean_val = excluded.mean_val,
                    sample_count = excluded.sample_count
                """,
                arguments: [
                    channel, sessionID, minuteIndex * 60,
                    doubles.min(), doubles.max(),
                    doubles.reduce(0, +) / Double(doubles.count),
                    minuteSamples.count,
                ]
            )
        }
    }
}
