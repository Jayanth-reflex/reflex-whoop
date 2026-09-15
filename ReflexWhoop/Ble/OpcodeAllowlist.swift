import Foundation

/// The single choke point every outgoing BLE command must pass through. Per
/// docs/PROTOCOL-GEN5.md's "Safety rails": the flash read cursor is
/// shared with the official WHOOP app across connections, and draining it could
/// starve the official app and corrupt real recovery/strain scores. Nothing in
/// this codebase constructs and sends a command frame except through
/// `OpcodeAllowlist.assertAllowed`.
enum OpcodeAllowlist {
    struct ForbiddenOpcodeError: Error, CustomStringConvertible {
        let opcode: UInt8
        var description: String {
            "Opcode 0x\(String(opcode, radix: 16, uppercase: true)) is not on the BLE allowlist " +
            "(see docs/PROTOCOL-GEN5.md's safety rails) — refusing to send."
        }
    }

    /// Throws unless `opcode` is one of `Ble.AllowedOpcode`'s exact raw values.
    /// Call this immediately before every `BandConnection.send`, no exceptions.
    static func assertAllowed(_ opcode: UInt8) throws {
        guard Ble.AllowedOpcode(rawValue: opcode) != nil else {
            throw ForbiddenOpcodeError(opcode: opcode)
        }
    }

    static func isAllowed(_ opcode: UInt8) -> Bool {
        Ble.AllowedOpcode(rawValue: opcode) != nil
    }

    /// True for packet types the app must log-and-discard without ever ACKing,
    /// per docs/PROTOCOL-GEN5.md's "Safety rails": "A `0x2F` or `0x31` packet is
    /// logged and never acknowledged, whatever the app thinks it asked for. No
    /// ACK, no cursor movement." `BandConnection` checks this on every inbound
    /// frame regardless of what it thinks it asked for.
    static func mustNeverAck(packetType: UInt8) -> Bool {
        packetType == Ble.PacketType.historical.rawValue || packetType == Ble.PacketType.syncMarker.rawValue
    }
}
