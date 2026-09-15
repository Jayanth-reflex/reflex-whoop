import Foundation

/// Decodes the one field confirmed in `docs/PROTOCOL-GEN5.md`'s "Session 2"
/// findings: the realtime compact-HR record (inner packet_type `0x28`) has a
/// direct, unscaled heart-rate byte at offset 8. Everything else in that
/// 20-byte record is unmapped — per docs/PROTOCOL-GEN5.md, "only decode a field once
/// captured frames confirm it," so this decoder exposes nothing else.
enum RealtimeHRDecoder {
    /// `inner` is the envelope's inner packet — `Gen5Envelope.Frame.inner`,
    /// not the raw notification. Returns `nil` for anything that isn't a
    /// well-formed `0x28` record (wrong packet type, or too short to have a
    /// byte at offset 8), rather than guessing.
    static func heartRateBpm(inner: Data) -> UInt8? {
        guard inner.count >= 9, inner.first == 0x28 else { return nil }
        return inner[inner.startIndex + 8]
    }
}
