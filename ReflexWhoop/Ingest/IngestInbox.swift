import Foundation
import GRDB

/// The append-only landing zone for every byte either data source produces, before
/// any decoding happens. See the design note in `Migrator.createInboxLayer`: writing
/// here first means a decoder bug is never data loss — fix the decoder, bump its
/// version, and replay.
enum IngestInbox {
    enum Source: String {
        case api
        case ble
    }

    /// Appends a raw payload and returns its `seq`. API payloads are stored
    /// zlib-compressed (JSON compresses ~8x and it's free); BLE frames are stored
    /// raw since they're already dense binary and the write path is latency-sensitive.
    @discardableResult
    static func append(
        _ db: GRDB.Database,
        source: Source,
        kind: String,
        payload: Data,
        receivedAt: Date = Date()
    ) throws -> Int64 {
        let (codec, bytes): (String, Data) = {
            switch source {
            case .api:
                let (c, compressed) = ChunkCompression.compress(payload, using: .zlib)
                return (c.rawValue, compressed)
            case .ble:
                return ("raw", payload)
            }
        }()

        try db.execute(
            sql: """
            INSERT INTO ingest_inbox (source, kind, received_at, payload, codec)
            VALUES (?, ?, ?, ?, ?)
            """,
            arguments: [source.rawValue, kind, Int64(receivedAt.timeIntervalSince1970), bytes, codec]
        )
        return db.lastInsertedRowID
    }

    /// Reads back the original payload for a given inbox row, reversing whatever
    /// compression `append` applied.
    static func payload(for row: Row) -> Data {
        let codecRaw: String = row["codec"]
        let payload: Data = row["payload"]
        guard let codec = ChunkBlobCodec(rawValue: codecRaw), codec != .none else {
            return payload
        }
        // API JSON payloads are small (well under 1 MB); a generous fixed hint avoids
        // a decompression retry loop in the common case.
        return ChunkCompression.decompress(payload, using: codec, expectedSize: 1 << 20)
    }

    /// Rows the normalizer hasn't processed yet, oldest first.
    static func fetchUndecoded(_ db: GRDB.Database, source: Source, limit: Int = 500) throws -> [Row] {
        try Row.fetchAll(
            db,
            sql: """
            SELECT * FROM ingest_inbox
            WHERE source = ? AND decoded_at IS NULL
            ORDER BY seq ASC
            LIMIT ?
            """,
            arguments: [source.rawValue, limit]
        )
    }

    static func markDecoded(_ db: GRDB.Database, seq: Int64, decoderVersion: Int, at date: Date = Date()) throws {
        try db.execute(
            sql: "UPDATE ingest_inbox SET decoded_at = ?, decoder_version = ? WHERE seq = ?",
            arguments: [Int64(date.timeIntervalSince1970), decoderVersion, seq]
        )
    }
}
