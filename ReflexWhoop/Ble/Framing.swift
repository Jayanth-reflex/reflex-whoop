import Foundation

/// CRC algorithms used by the Gen 5 envelope. These two functions are the only
/// part of this file that's a *confirmed fact* rather than a hypothesis — they
/// implement the standard CRC-16/MODBUS and CRC-32 (IEEE 802.3) algorithms and
/// are verified against the textbook check values for ASCII "123456789" in
/// `FramingTests`, independent of anything WHOOP-specific.
enum Crc {
    /// CRC-16/MODBUS: init 0xFFFF, poly 0xA001 (reflected 0x8005), no xorout.
    /// Check value for "123456789" is 0x4B37.
    static func modbus16(_ bytes: some Sequence<UInt8>) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for byte in bytes {
            crc ^= UInt16(byte)
            for _ in 0..<8 {
                if crc & 1 != 0 {
                    crc = (crc >> 1) ^ 0xA001
                } else {
                    crc >>= 1
                }
            }
        }
        return crc
    }

    /// CRC-32 (IEEE 802.3 / zlib): init 0xFFFFFFFF, poly 0xEDB88320 (reflected),
    /// xorout 0xFFFFFFFF. Check value for "123456789" is 0xCBF43926.
    static func ieee32(_ bytes: some Sequence<UInt8>) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                if crc & 1 != 0 {
                    crc = (crc >> 1) ^ 0xEDB8_8320
                } else {
                    crc >>= 1
                }
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}

/// The Gen 5 envelope, built from docs/design.md's diff table:
/// `[0xAA][0x01][len][field][CRC-16/MODBUS][inner][CRC-32]`.
///
/// **This layout is a hypothesis, not a confirmed fact** — the field widths
/// below (`len` as u16 LE, `field` as one reserved byte, CRC-16 computed over
/// `len`+`field`, inner padded to a multiple of 4 before the CRC-32 trailer)
/// are this app's best reading of the design doc's diff table, chosen by
/// mirroring Gen 4's known-good structure (`[0xAA][u16 len][CRC8(len)][inner
/// padded /4][u32 CRC32]`) with Gen 5's documented widening of the length
/// checksum from CRC-8 to CRC-16 and one new header byte. The Gen 5 discovery
/// spike (docs/design.md, "Gen 5 discovery spike") exists specifically to
/// confirm or correct this — see `docs/PROTOCOL-GEN5.md` once written.
///
/// Nothing downstream trusts this decoder blindly: `FrameReassembler` verifies
/// both CRCs before treating a candidate frame as real, and every raw fragment
/// is logged to `ingest_inbox` regardless of whether reassembly or CRC
/// verification succeeds — a wrong hypothesis loses no data, only defers
/// decoding until the hypothesis is fixed.
enum Gen5Envelope {
    static let marker: UInt8 = 0xAA
    static let version: UInt8 = 0x01
    static let headerSize = 7 // marker + version + len(2) + field(1) + crc16(2)
    static let trailerSize = 4 // crc32

    struct Frame {
        let field: UInt8
        let inner: Data // padded to a multiple of 4, per the Gen 4 precedent
        let headerCrcValid: Bool
        let trailerCrcValid: Bool
    }

    /// Builds an outgoing command envelope around `inner` (the unpadded inner
    /// packet: `[packet_type][seq][opcode][body…]`). Padding and both CRCs are
    /// computed here so callers never hand-assemble bytes.
    static func encode(field: UInt8, inner: Data) -> Data {
        let paddedLen = (inner.count + 3) / 4 * 4
        var padded = inner
        padded.append(Data(repeating: 0, count: paddedLen - inner.count))

        let len = UInt16(inner.count)
        let lenBytes: [UInt8] = [UInt8(len & 0xFF), UInt8(len >> 8)]
        let crc16 = Crc.modbus16(lenBytes + [field])

        var frame = Data()
        frame.append(marker)
        frame.append(version)
        frame.append(contentsOf: lenBytes)
        frame.append(field)
        frame.append(UInt8(crc16 & 0xFF))
        frame.append(UInt8(crc16 >> 8))
        frame.append(padded)

        let crc32 = Crc.ieee32(padded)
        frame.append(UInt8(crc32 & 0xFF))
        frame.append(UInt8((crc32 >> 8) & 0xFF))
        frame.append(UInt8((crc32 >> 16) & 0xFF))
        frame.append(UInt8((crc32 >> 24) & 0xFF))
        return frame
    }

    /// Total byte length this hypothesis predicts for a frame whose header
    /// claims inner length `len` — used by `FrameReassembler` to know how many
    /// bytes to wait for. Returns `nil` if `len` is implausibly large (garbage
    /// header), so the reassembler can resync instead of buffering forever.
    static func predictedFrameLength(innerLen: Int) -> Int? {
        guard innerLen >= 0, innerLen <= 8192 else { return nil }
        let paddedLen = (innerLen + 3) / 4 * 4
        return headerSize + paddedLen + trailerSize
    }

    /// Decodes a byte range already known to be one complete candidate frame
    /// (i.e. `bytes.count == predictedFrameLength(innerLen:)` for the `len`
    /// read from this same header). Verifies both CRCs; never throws — a bad
    /// frame comes back with the relevant `*CrcValid` flag false so the caller
    /// can log-and-discard rather than crash on a wrong hypothesis.
    static func decode(_ bytes: Data) -> Frame? {
        guard bytes.count >= headerSize + trailerSize, bytes[bytes.startIndex] == marker else { return nil }
        let b = [UInt8](bytes)
        let len = Int(b[2]) | (Int(b[3]) << 8)
        let field = b[4]
        let headerCrc = UInt16(b[5]) | (UInt16(b[6]) << 8)
        let headerCrcValid = Crc.modbus16([b[2], b[3], field]) == headerCrc

        let paddedLen = (len + 3) / 4 * 4
        guard headerSize + paddedLen + trailerSize == bytes.count else { return nil }

        let innerRange = headerSize..<(headerSize + paddedLen)
        let inner = Data(b[innerRange])
        let trailerStart = headerSize + paddedLen
        let trailerCrc = UInt32(b[trailerStart])
            | (UInt32(b[trailerStart + 1]) << 8)
            | (UInt32(b[trailerStart + 2]) << 16)
            | (UInt32(b[trailerStart + 3]) << 24)
        let trailerCrcValid = Crc.ieee32(inner) == trailerCrc

        return Frame(field: field, inner: inner, headerCrcValid: headerCrcValid, trailerCrcValid: trailerCrcValid)
    }
}

/// Buffers fragmented BLE notifications into complete envelope candidates,
/// length-based rather than triggered on the next `0xAA` byte — per
/// docs/design.md: "sensor payloads contain 0xAA bytes constantly. This is the
/// single most common way a decoder silently corrupts data." If the header's
/// claimed length turns out to be wrong (Gen5Envelope's hypothesis is off, or
/// we're mid-stream from before we started listening), this resyncs by
/// scanning for the next plausible marker rather than getting stuck.
///
/// This never drops data from the inbox's point of view — the caller logs
/// every raw fragment to `ingest_inbox` on arrival, before handing it to this
/// reassembler. This class only decides when a *candidate complete frame* is
/// ready to attempt-decode for live diagnostics (e.g. the HELLO round-trip
/// check); it is not the source of truth for what was received.
final class FrameReassembler {
    private var buffer = Data()

    /// Feeds one raw notification's bytes in. Returns any complete candidate
    /// frames extracted this call (usually zero or one, but a burst of
    /// small notifications can complete more than one frame per call).
    func feed(_ fragment: Data) -> [Gen5Envelope.Frame] {
        buffer.append(fragment)
        var frames: [Gen5Envelope.Frame] = []

        while true {
            guard let markerIndex = buffer.firstIndex(of: Gen5Envelope.marker) else {
                buffer.removeAll()
                break
            }
            if markerIndex > buffer.startIndex {
                buffer.removeSubrange(buffer.startIndex..<markerIndex)
            }
            guard buffer.count >= Gen5Envelope.headerSize else { break }

            let b = [UInt8](buffer.prefix(Gen5Envelope.headerSize))
            let len = Int(b[2]) | (Int(b[3]) << 8)
            guard let total = Gen5Envelope.predictedFrameLength(innerLen: len) else {
                // Implausible length — this 0xAA was a false positive inside
                // sensor data. Drop it and keep scanning from the next byte.
                buffer.removeFirst()
                continue
            }
            guard buffer.count >= total else { break } // wait for more fragments

            let candidate = buffer.prefix(total)
            buffer.removeSubrange(buffer.startIndex..<buffer.index(buffer.startIndex, offsetBy: total))
            if let frame = Gen5Envelope.decode(candidate) {
                frames.append(frame)
            }
        }
        return frames
    }
}
