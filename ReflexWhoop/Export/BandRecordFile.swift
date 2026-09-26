import Foundation

/// One `ble_sessions/<id>.bin` file in an export, written as it goes rather than built
/// in memory: a session can hold hundreds of thousands of frames.
///
/// The format is self-describing so the frames replay without database access, one
/// record per inbox row: `[u8 kindLen][kind ascii][i64 LE receivedAt][u32 LE
/// payloadLen][payload bytes]`.
final class BandRecordFile {
    enum FormatError: Error {
        /// The kind is stored with a one-byte length. Kinds are characteristic UUID
        /// strings, 36 bytes, so this means something other than a band frame got here.
        case kindTooLong(String)
    }

    private let handle: FileHandle
    private var buffer = Data()
    private(set) var byteCount = 0

    /// Flushed to disk in chunks this size, which keeps memory flat however long the
    /// session is without a write call per frame.
    private static let flushThreshold = 256 * 1024

    init(url: URL) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
    }

    func append(kind: String, receivedAt: Int64, payload: Data) throws {
        let kindBytes = Data(kind.utf8)
        guard kindBytes.count <= Int(UInt8.max) else { throw FormatError.kindTooLong(kind) }

        buffer.append(UInt8(kindBytes.count))
        buffer.append(kindBytes)
        withUnsafeBytes(of: receivedAt.littleEndian) { buffer.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(payload.count).littleEndian) { buffer.append(contentsOf: $0) }
        buffer.append(payload)
        byteCount += 1 + kindBytes.count + 8 + 4 + payload.count

        if buffer.count >= Self.flushThreshold { try flush() }
    }

    func close() throws {
        try flush()
        try handle.close()
    }

    private func flush() throws {
        guard !buffer.isEmpty else { return }
        try handle.write(contentsOf: buffer)
        buffer.removeAll(keepingCapacity: true)
    }
}
