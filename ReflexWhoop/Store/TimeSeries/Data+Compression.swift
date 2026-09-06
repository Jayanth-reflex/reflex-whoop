import Foundation
import Compression

/// Thin wrapper over Apple's Compression framework — no third-party dependency for
/// something the OS already ships. Used as the final stage after `ChunkCodec`'s
/// delta/zigzag/varint encoding: PPG and other noisy channels still compress another
/// 1.5-3x on top of delta encoding because consecutive varint bytes repeat.
enum ChunkBlobCodec: String {
    case lzfse
    case zlib
    case none

    var algorithm: compression_algorithm? {
        switch self {
        case .lzfse: return COMPRESSION_LZFSE
        case .zlib: return COMPRESSION_ZLIB
        case .none: return nil
        }
    }
}

enum ChunkCompression {
    /// Compresses with the given codec, falling back to `.none` (store as-is) if
    /// compression would not actually shrink the data — true for very short chunks
    /// where the format overhead exceeds any savings.
    static func compress(_ data: Data, using codec: ChunkBlobCodec) -> (codec: ChunkBlobCodec, bytes: Data) {
        guard let algorithm = codec.algorithm, !data.isEmpty else {
            return (.none, data)
        }

        let dstCapacity = max(data.count, 64)
        var dstBuffer = [UInt8](repeating: 0, count: dstCapacity)

        let compressedSize = data.withUnsafeBytes { srcPtr -> Int in
            guard let srcBase = srcPtr.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return dstBuffer.withUnsafeMutableBufferPointer { dstPtr -> Int in
                guard let dstBase = dstPtr.baseAddress else { return 0 }
                return compression_encode_buffer(
                    dstBase, dstCapacity,
                    srcBase, data.count,
                    nil, algorithm
                )
            }
        }

        guard compressedSize > 0, compressedSize < data.count else {
            // Compression failed or didn't help (buffer too small, or data already dense).
            return (.none, data)
        }

        return (codec, Data(dstBuffer.prefix(compressedSize)))
    }

    /// Decompresses `data`, which was compressed by `compress` with `codec`.
    /// `expectedSize` is a hint (typically `sample_count * bytesPerSample` upper
    /// bound); the buffer grows and retries if the hint was too small, so a wrong
    /// hint costs a retry, never a correctness failure.
    static func decompress(_ data: Data, using codec: ChunkBlobCodec, expectedSize: Int) -> Data {
        guard let algorithm = codec.algorithm, !data.isEmpty else {
            return data
        }

        var capacity = max(expectedSize, data.count * 4, 256)
        let maxCapacity = max(capacity, 1 << 28) // 256 MB hard ceiling — a single chunk should never approach this

        while capacity <= maxCapacity {
            var dstBuffer = [UInt8](repeating: 0, count: capacity)

            let decodedSize = data.withUnsafeBytes { srcPtr -> Int in
                guard let srcBase = srcPtr.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return dstBuffer.withUnsafeMutableBufferPointer { dstPtr -> Int in
                    guard let dstBase = dstPtr.baseAddress else { return 0 }
                    return compression_decode_buffer(
                        dstBase, capacity,
                        srcBase, data.count,
                        nil, algorithm
                    )
                }
            }

            if decodedSize > 0 && decodedSize < capacity {
                return Data(dstBuffer.prefix(decodedSize))
            }
            capacity *= 2
        }

        assertionFailure("ChunkCompression.decompress: exceeded max capacity — corrupt chunk or bad expectedSize hint")
        return Data()
    }
}
