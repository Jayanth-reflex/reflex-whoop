import CoreBluetooth
import Foundation
import GRDB
import Observation

/// Orchestrates the Phase 4 discovery spike (docs/design.md, "Gen 5 discovery
/// spike"): connect, send the safe read-only command sequence, and log every
/// raw notification to `ingest_inbox` untouched for later offline analysis.
/// This is deliberately dumb about *meaning* — its only judgment call is which
/// commands are safe to send (delegated entirely to `OpcodeAllowlist` via
/// `BandConnection.send`), and it opportunistically runs frames through
/// `FrameReassembler` purely to show the user a live "does our envelope
/// hypothesis check out" signal. The inbox row is the source of truth either way.
@Observable
@MainActor
final class SpikeRecorder {
    private let dbPool: DatabasePool
    let connection = BandConnection()

    private(set) var sessionID: String?
    private(set) var frameCount = 0
    private(set) var byteCount = 0
    private(set) var reassembledFrameCount = 0
    private(set) var validCrcFrameCount = 0
    private(set) var lastHelloInner: Data?
    /// Per `RealtimeHRDecoder` / docs/PROTOCOL-GEN5.md — the one sensor field
    /// confirmed so far. `nil` until a `0x28` record has actually arrived.
    private(set) var lastHeartRateBpm: UInt8?

    private var reassembler = FrameReassembler()
    private var sentSafeSequence = false

    init(dbPool: DatabasePool) {
        self.dbPool = dbPool
        connection.onRawFrame = { [weak self] uuid, data, receivedAt in
            self?.handleRawFrame(characteristic: uuid, data: data, receivedAt: receivedAt)
        }
    }

    var connectionState: BandConnection.ConnectionState { connection.state }

    func startSession(mode: String = "spike_hr_imu_optical") throws {
        let id = UUID().uuidString
        let now = Date()
        // Channels this session *intends* to enable via beginSafeCommandSequence
        // — not a claim about what was actually decoded (docs/PROTOCOL-GEN5.md
        // has confirmed only "hr" so far).
        let channelsJSON = #"["hr","imu","optical"]"#
        try dbPool.write { db in
            try db.execute(
                sql: """
                INSERT INTO ble_sessions (id, started_at, mode, channels_json, sample_count, dropped_count, byte_count)
                VALUES (?, ?, ?, ?, 0, 0, 0)
                """,
                arguments: [id, Int64(now.timeIntervalSince1970), mode, channelsJSON]
            )
        }
        sessionID = id
        frameCount = 0
        byteCount = 0
        reassembledFrameCount = 0
        validCrcFrameCount = 0
        lastHelloInner = nil
        sentSafeSequence = false
        reassembler = FrameReassembler()
        connection.start()
    }

    func stopSession(reason: String = "user_stopped") {
        guard let id = sessionID else { return }
        let frameCount = frameCount
        let byteCount = byteCount
        Task {
            try? await dbPool.write { db in
                try db.execute(
                    sql: """
                    UPDATE ble_sessions
                    SET ended_at = ?, sample_count = ?, byte_count = ?, ended_reason = ?
                    WHERE id = ?
                    """,
                    arguments: [Int64(Date().timeIntervalSince1970), frameCount, byteCount, reason, id]
                )
            }
        }
        connection.disconnect()
        sessionID = nil
    }

    /// Sends the safe, read-only-plus-live-stream sequence from docs/design.md's
    /// "What we stream": identity/battery first (to validate the envelope
    /// round-trips before trusting anything else), then the realtime toggles —
    /// HR, IMU, and optical (R21, the only source of true respiratory rate),
    /// all opcodes from the allowlist's live-only set. Called once from the UI
    /// when `connectionState == .ready`; harmless to call again, it's idempotent.
    func beginSafeCommandSequence() {
        guard !sentSafeSequence else { return }
        sentSafeSequence = true
        try? connection.send(opcode: .getHelloHarvard)
        try? connection.send(opcode: .getBatteryLevel)
        try? connection.send(opcode: .toggleRealtimeHR, body: Data([0x01]))
        try? connection.send(opcode: .sendR10R11Realtime, body: Data([0x01]))
        try? connection.send(opcode: .toggleImuMode, body: Data([0x01]))
        try? connection.send(opcode: .enableOpticalData, body: Data([0x01]))
        try? connection.send(opcode: .toggleOpticalMode, body: Data([0x01]))
    }

    private func handleRawFrame(characteristic: CBUUID, data: Data, receivedAt: Date) {
        frameCount += 1
        byteCount += data.count

        // Inbox-first: this write happens unconditionally, before any attempt
        // to interpret the bytes. A wrong envelope hypothesis below loses no
        // data — it only fails to light up the "confirmed" indicator.
        Task {
            try? await dbPool.write { db in
                try IngestInbox.append(db, source: .ble, kind: characteristic.uuidString, payload: data, receivedAt: receivedAt)
            }
        }

        for frame in reassembler.feed(data) {
            reassembledFrameCount += 1
            guard frame.headerCrcValid, frame.trailerCrcValid else { continue }
            validCrcFrameCount += 1
            if lastHelloInner == nil {
                lastHelloInner = frame.inner
            }
            if let bpm = RealtimeHRDecoder.heartRateBpm(inner: frame.inner) {
                lastHeartRateBpm = bpm
            }
        }
    }
}
