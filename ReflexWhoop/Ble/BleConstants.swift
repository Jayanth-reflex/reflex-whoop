import CoreBluetooth

/// WHOOP 5.0's custom GATT service and the opcode vocabulary of its command
/// protocol. UUIDs and the safety split (allowed vs. permanently forbidden) are
/// taken directly from docs/design.md's "Source B — BLE direct to the band"
/// section — do not add or change an opcode set here without updating that doc.
enum Ble {
    /// Gen 5's custom service. Differs from Gen 4's `61080001-…` (see
    /// docs/DECISIONS.md and docs/design.md's Gen4/Gen5 diff table).
    static let serviceUUID = CBUUID(string: "fd4b0001-cce1-4033-93ce-002d5875f58a")

    static let writeCharacteristicUUID = CBUUID(string: "fd4b0002-cce1-4033-93ce-002d5875f58a")
    static let commandResponseCharacteristicUUID = CBUUID(string: "fd4b0003-cce1-4033-93ce-002d5875f58a")
    static let eventsCharacteristicUUID = CBUUID(string: "fd4b0004-cce1-4033-93ce-002d5875f58a")
    static let dataCharacteristicUUID = CBUUID(string: "fd4b0005-cce1-4033-93ce-002d5875f58a")
    /// New in 5.0 — purpose unconfirmed until the discovery spike maps it.
    static let unknown0007CharacteristicUUID = CBUUID(string: "fd4b0007-cce1-4033-93ce-002d5875f58a")

    /// Every notify characteristic we subscribe to, in the order the spike logs
    /// them — kept as one list so `BandConnection` can't accidentally miss one.
    static let notifyCharacteristicUUIDs: [CBUUID] = [
        commandResponseCharacteristicUUID,
        eventsCharacteristicUUID,
        dataCharacteristicUUID,
        unknown0007CharacteristicUUID,
    ]

    /// Inner-packet `packet_type` byte (position 0 of the inner packet, per
    /// docs/design.md — unchanged between Gen 4 and Gen 5).
    enum PacketType: UInt8 {
        case command = 0x23
        case response = 0x24
        case realtimeCompactHR = 0x28
        case realtimeRaw = 0x2B // R10
        case historical = 0x2F
        case event = 0x30
        case syncMarker = 0x31
        case imuA = 0x33
        case imuB = 0x34
    }

    /// Every opcode this app is willing to send, with the reason it's safe.
    /// This is the *complete* set — `OpcodeAllowlist` is the single choke point
    /// that checks against it, and there is no other way to originate a write.
    enum AllowedOpcode: UInt8, CaseIterable {
        case getHelloHarvard = 0x23 // read-only identity/battery/wrist
        case getBatteryLevel = 0x1A // read-only (0x180F standard char is buggy, always 100%)
        case getDataRange = 0x22 // read-only backlog *window query* — does not move the cursor
        case toggleRealtimeHR = 0x03 // live stream toggle, no flash access
        case sendR10R11Realtime = 0x3F // live HR + IMU
        case toggleImuMode = 0x6A // live IMU
        case enableOpticalData = 0x6B // wrist-gated optical, live only
        case toggleOpticalMode = 0x6C // live optical
    }

    /// Permanently forbidden — never sent, not behind a flag. Kept as an
    /// explicit list (rather than "everything not in AllowedOpcode") purely so
    /// the unit test can assert each one by name against docs/design.md's table;
    /// the actual enforcement in `OpcodeAllowlist` is allowlist-based either way.
    enum ForbiddenOpcode: UInt8, CaseIterable {
        case sendHistoricalData = 0x16 // starts flash drain
        case historicalDataResult = 0x17 // the ACK that advances the shared cursor
        case setReadPointer = 0x21 // moves the shared cursor
        case abortHistoricalTransmits = 0x14 // only meaningful if draining
        case togglePersistentR21 = 0x9A // forces optical, sticks the LED on
        case rebootStrap = 0x1D // hard reset
        case setClock = 0x0A // writes the band's RTC
    }
}
