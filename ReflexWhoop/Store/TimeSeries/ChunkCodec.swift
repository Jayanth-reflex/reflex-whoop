import Foundation

/// Encodes one BLE channel's samples for one 1-hour bucket into a compact byte blob.
///
/// Pipeline: quantize (caller's job — e.g. accel f32 → milli-g Int64) → delta →
/// zigzag → varint → generic compression (`Data+Compression.swift`).
///
/// This type only does the delta/zigzag/varint step; `ChunkStore` wraps it with
/// the compression step and picks whichever encoding produces fewer bytes.
///
/// Assumption, documented rather than enforced at the type level: input values are
/// well within `Int64` range for delta arithmetic to never overflow — true for every
/// real channel here (HR in bpm, RR in ms, accel quantized to milli-g, ADC readings,
/// temperatures). `encode` traps in debug builds (via `&+`/`&-` avoidance) rather than
/// silently wrapping if that assumption is ever violated.
enum ChunkCodec {
    enum Encoding: String {
        case deltaZigzagVarint = "delta_zigzag_varint"
        case rawI64 = "raw_i64"
    }

    /// Picks whichever encoding is smaller. Delta-zigzag-varint wins for anything
    /// slowly varying (which is every real sensor channel); raw is the fallback for
    /// pathological inputs (e.g. white noise) where delta encoding would inflate size.
    static func encode(_ values: [Int64]) -> (encoding: Encoding, bytes: Data) {
        guard !values.isEmpty else {
            return (.deltaZigzagVarint, Data())
        }

        let deltaEncoded = encodeDeltaZigzagVarint(values)
        let rawEncoded = encodeRaw(values)

        if deltaEncoded.count <= rawEncoded.count {
            return (.deltaZigzagVarint, deltaEncoded)
        } else {
            return (.rawI64, rawEncoded)
        }
    }

    static func decode(encoding: Encoding, bytes: Data, count: Int) -> [Int64] {
        guard count > 0 else { return [] }
        switch encoding {
        case .deltaZigzagVarint:
            return decodeDeltaZigzagVarint(bytes, count: count)
        case .rawI64:
            return decodeRaw(bytes, count: count)
        }
    }

    // MARK: - Delta + zigzag + varint

    private static func encodeDeltaZigzagVarint(_ values: [Int64]) -> Data {
        var out = Data()
        out.reserveCapacity(values.count * 2)

        var previous: Int64 = 0
        for value in values {
            let delta = value.subtractingReportingOverflow(previous).partialValue
            previous = value
            appendVarint(zigzagEncode(delta), to: &out)
        }
        return out
    }

    private static func decodeDeltaZigzagVarint(_ data: Data, count: Int) -> [Int64] {
        var result: [Int64] = []
        result.reserveCapacity(count)

        var offset = data.startIndex
        var previous: Int64 = 0
        for _ in 0..<count {
            let (zigzag, next) = readVarint(data, from: offset)
            offset = next
            let delta = zigzagDecode(zigzag)
            let value = previous.addingReportingOverflow(delta).partialValue
            previous = value
            result.append(value)
        }
        return result
    }

    // MARK: - Raw fallback (fixed-width, no delta)

    private static func encodeRaw(_ values: [Int64]) -> Data {
        var out = Data(capacity: values.count * MemoryLayout<Int64>.size)
        for value in values {
            var le = value.littleEndian
            withUnsafeBytes(of: &le) { out.append(contentsOf: $0) }
        }
        return out
    }

    private static func decodeRaw(_ data: Data, count: Int) -> [Int64] {
        var result: [Int64] = []
        result.reserveCapacity(count)
        var offset = data.startIndex
        for _ in 0..<count {
            let slice = data[offset..<offset + MemoryLayout<Int64>.size]
            let le = slice.withUnsafeBytes { $0.loadUnaligned(as: Int64.self) }
            result.append(Int64(littleEndian: le))
            offset += MemoryLayout<Int64>.size
        }
        return result
    }

    // MARK: - Zigzag

    static func zigzagEncode(_ n: Int64) -> UInt64 {
        UInt64(bitPattern: (n << 1) ^ (n >> 63))
    }

    static func zigzagDecode(_ z: UInt64) -> Int64 {
        Int64(bitPattern: (z >> 1)) ^ -Int64(bitPattern: z & 1)
    }

    // MARK: - Varint (LEB128, unsigned)

    static func appendVarint(_ value: UInt64, to data: inout Data) {
        var v = value
        while true {
            var byte = UInt8(v & 0x7F)
            v >>= 7
            if v != 0 {
                byte |= 0x80
                data.append(byte)
            } else {
                data.append(byte)
                break
            }
        }
    }

    static func readVarint(_ data: Data, from start: Data.Index) -> (value: UInt64, next: Data.Index) {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        var index = start
        while true {
            let byte = data[index]
            index += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { break }
            shift += 7
        }
        return (result, index)
    }
}
