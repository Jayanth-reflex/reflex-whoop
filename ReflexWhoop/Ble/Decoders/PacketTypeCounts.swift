import Foundation

/// Per-`packet_type` frame tally for the Live screen's "channel activity"
/// diagnostic. Exists to answer one question cheaply, without any decode
/// work: is a given channel (IMU `0x33`/`0x34`, R10 `0x2B`, R21/r22 — whatever
/// packet_type those turn out to be) producing *any* frames at all, or is
/// `SENSORS: No active sources` (docs/PROTOCOL-GEN5.md, session 4) still true?
/// Keyed by the raw byte rather than `Ble.PacketType` so an unrecognized type
/// (a candidate r22/r26 record) still gets counted instead of silently
/// dropped.
struct PacketTypeCounts {
    private(set) var counts: [UInt8: Int] = [:]

    mutating func record(_ packetType: UInt8) {
        counts[packetType, default: 0] += 1
    }

    /// Sorted by frequency descending, for stable UI ordering.
    var sortedByCount: [(packetType: UInt8, count: Int)] {
        counts.map { ($0.key, $0.value) }.sorted { $0.count > $1.count }
    }

    static func label(for packetType: UInt8) -> String {
        if let known = Ble.PacketType(rawValue: packetType) {
            return "\(known)"
        }
        return String(format: "0x%02X (unmapped)", packetType)
    }
}
