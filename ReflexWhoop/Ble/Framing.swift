import Foundation

/// CRC algorithms used by the Gen 5 envelope. These two functions are the only
/// part of this file that was already a confirmed fact before the discovery
/// spike ran — they implement the standard CRC-16/MODBUS and CRC-32 (IEEE
/// 802.3) algorithms and are verified against the textbook check values for
/// ASCII "123456789" in `FramingTests`, independent of anything WHOOP-specific.
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

/// The Gen 5 envelope. **Confirmed** against a real ~10-minute session on the
/// user's own band — 711/711 captured frames across all three notify
/// characteristics matched this exact structure with a valid CRC-16 *and* a
/// valid CRC-32, zero exceptions. See `docs/PROTOCOL-GEN5.md` for the full
/// derivation (found by brute-force searching which byte range's CRC-32
/// matched the trailing 4 bytes across 14 near-identical real frames).
///
/// ```
/// byte 0      0xAA                  marker
/// byte 1      0x01                  version (constant in every sample seen)
/// bytes 2-3   u16 LE  len            = field(2) + crc16(2) + inner.count
/// bytes 4-5   u16 LE  field          constant 0x0001 in every sample seen —
///                                    purpose unconfirmed, meaning unknown
/// bytes 6-7   u16 LE  crc16          CRC-16/MODBUS over bytes[0..<6]
/// bytes 8..   inner   (len - 4)      [packet_type][seq][opcode/event_id][body]
/// last 4      u32 LE  crc32          CRC-32 (IEEE 802.3) over `inner` only
/// ```
///
/// This superseded an earlier hypothesis (7-byte header, 1-byte field, inner
/// padded to a multiple of 4) modeled on Gen 4's structure — that guess turned
/// out to be wrong on every count except the marker and version bytes. There
/// is **no padding** here: `len` and the total frame length are exact byte
/// counts.
///
/// Nothing downstream trusts this decoder blindly: `FrameReassembler` verifies
/// both CRCs before treating a candidate frame as real, and every raw fragment
/// is logged to `ingest_inbox` regardless of whether reassembly or CRC
/// verification succeeds.
enum Gen5Envelope {
    static let marker: UInt8 = 0xAA
    static let version: UInt8 = 0x01
    static let headerSize = 8 // marker + version + len(2) + field(2) + crc16(2)
    static let trailerSize = 4 // crc32

    struct Frame {
        let field: UInt16
        let inner: Data // exact length, no padding
        let headerCrcValid: Bool
        let trailerCrcValid: Bool
    }

    /// Builds an outgoing command envelope around `inner` (the exact inner
    /// packet: `[packet_type][seq][opcode][body…]`, no padding). `field` is
    /// always `1` for every outgoing/incoming frame observed so far — see the
    /// doc comment above — but is a parameter rather than hardcoded so a
    /// future session that discovers a different meaning doesn't need this
    /// signature to change.
    static func encode(field: UInt16, inner: Data) -> Data {
        let len = UInt16(inner.count + 4)
        var frame = Data()
        frame.append(marker)
        frame.append(version)
        frame.append(UInt8(len & 0xFF))
        frame.append(UInt8(len >> 8))
        frame.append(UInt8(field & 0xFF))
        frame.append(UInt8(field >> 8))

        let crc16 = Crc.modbus16(frame) // over bytes[0..<6], i.e. the frame so far
        frame.append(UInt8(crc16 & 0xFF))
        frame.append(UInt8(crc16 >> 8))

        frame.append(inner)

        let crc32 = Crc.ieee32(inner)
        frame.append(UInt8(crc32 & 0xFF))
        frame.append(UInt8((crc32 >> 8) & 0xFF))
        frame.append(UInt8((crc32 >> 16) & 0xFF))
        frame.append(UInt8((crc32 >> 24) & 0xFF))
        return frame
    }

    /// Total byte length this predicts for a frame whose header claims field
    /// `len`, used by `FrameReassembler` to know how many bytes to wait for.
    /// Returns `nil` if `len` is too small to be real (must at least cover
    /// `field`+`crc16`) or implausibly large (garbage header), so the
    /// reassembler can resync instead of buffering forever.
    static func predictedFrameLength(len: Int) -> Int? {
        guard len >= 4, len <= 8192 else { return nil }
        let innerLen = len - 4
        return headerSize + innerLen + trailerSize
    }

    /// Decodes a byte range already known to be one complete candidate frame
    /// (i.e. `bytes.count == predictedFrameLength(len:)` for the `len` read
    /// from this same header). Verifies both CRCs; never throws — a bad frame
    /// comes back with the relevant `*CrcValid` flag false so the caller can
    /// log-and-discard rather than crash on a wrong reading.
    static func decode(_ bytes: Data) -> Frame? {
        guard bytes.count >= headerSize + trailerSize, bytes[bytes.startIndex] == marker else { return nil }
        let b = [UInt8](bytes)
        let len = Int(b[2]) | (Int(b[3]) << 8)
        let field = UInt16(b[4]) | (UInt16(b[5]) << 8)
        let headerCrc = UInt16(b[6]) | (UInt16(b[7]) << 8)
        let headerCrcValid = Crc.modbus16(b[0..<6]) == headerCrc

        guard len >= 4 else { return nil }
        let innerLen = len - 4
        guard headerSize + innerLen + trailerSize == bytes.count else { return nil }

        let inner = Data(b[headerSize..<(headerSize + innerLen)])
        let trailerStart = headerSize + innerLen
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
/// single most common way a decoder silently corrupts data." If a header's
/// claimed length is implausible (garbage, or we tuned in mid-stream), this
/// resyncs by scanning for the next plausible marker rather than getting stuck.
///
/// This never drops data from the inbox's point of view — the caller logs
/// every raw fragment to `ingest_inbox` on arrival, before handing it to this
/// reassembler. This class only decides when a *candidate complete frame* is
/// ready to attempt-decode for live diagnostics; it is not the source of
/// truth for what was received.
///
/// Unexercised so far: the real session this was verified against (see
/// docs/PROTOCOL-GEN5.md) never fragmented — every notification was already a
/// complete frame, largest inner payload 112 bytes. Keep this for R21/r22,
/// which are expected to exceed one notification's MTU, but its resync
/// behavior against a *real* fragmented frame is still unconfirmed.
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
            guard let total = Gen5Envelope.predictedFrameLength(len: len) else {
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
