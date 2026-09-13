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
    private(set) var sessionStartedAt: Date?
    private(set) var frameCount = 0
    private(set) var byteCount = 0
    private(set) var reassembledFrameCount = 0
    private(set) var validCrcFrameCount = 0
    /// Per `RealtimeHRDecoder` / docs/PROTOCOL-GEN5.md — the one sensor field
    /// confirmed so far. `nil` until a `0x28` record has actually arrived.
    private(set) var lastHeartRateBpm: UInt8?
    /// Heart-rate records decoded this session.
    private(set) var heartRateReadingCount = 0
    /// The last 20 minutes of decoded heart rate, for the live chart.
    private(set) var recentHeartRate = HeartRateWindow(span: 20 * 60)
    /// Frame count per inner packet_type, across every CRC-valid frame this
    /// session — the "is this channel producing anything at all" diagnostic
    /// for IMU/R10/R21/r22, none of which have a confirmed decoder yet.
    private(set) var packetTypeCounts = PacketTypeCounts()
    /// Raw strings pulled from `fd4b0007`'s CBOR payload — see
    /// `DeviceMetadataDecoder`. Deduplicated in arrival order.
    private(set) var deviceMetadataStrings: [String] = []
    /// `R10Decoder`'s speculative read of the latest `0x2B` frame, if one has
    /// ever arrived — unconfirmed on Gen 5, see that type's doc comment.
    private(set) var lastR10Candidate: R10Decoder.Sample?
    /// `0x28` HR minus `R10Decoder`'s candidate HR, once both exist —
    /// docs/design.md's "free cross-check" (R10 vs compact HR should agree
    /// within ±1 bpm on a worn band), computed automatically the moment both
    /// sides of it exist instead of waiting for a manual comparison.
    private(set) var hrCrossCheckDiffBpm: Int?

    private var reassembler = FrameReassembler()
    private var sentSafeSequence = false
    private var lastWatermarkAt: Date?

    /// How often the session row's "last seen" watermark is refreshed while
    /// recording. Every real session so far ended by the app being killed
    /// rather than by `stopSession` running, which left `ended_at` NULL on all
    /// 15 of them — so the clean-stop path cannot be the only thing that ever
    /// records when a session ended.
    private static let watermarkInterval: TimeInterval = 30

    init(dbPool: DatabasePool) {
        self.dbPool = dbPool
        connection.onRawFrame = { [weak self] uuid, data, receivedAt in
            self?.handleRawFrame(characteristic: uuid, data: data, receivedAt: receivedAt)
        }
        // Re-enable streaming on every connection, not just the first: after a
        // reconnect the band has forgotten it was asked to stream, so a
        // long-running session that survived a disconnect would otherwise sit
        // connected and silent.
        connection.onReady = { [weak self] in
            guard let self, sessionID != nil else { return }
            sentSafeSequence = false
            Task { await self.beginSafeCommandSequence() }
        }
    }

    var connectionState: BandConnection.ConnectionState { connection.state }

    /// Continuous mode keeps the connection alive across disconnects and asks
    /// iOS to relaunch the app for Bluetooth events — see `BandConnection`'s
    /// `autoReconnect` and `start(restoreState:)`. Used when the band is being
    /// treated as a standing data source rather than something you watch.
    func startContinuousSession() throws {
        connection.autoReconnect = true
        try startSession(mode: "continuous", restoreState: true)
    }

    func startSession(mode: String = "spike_hr_imu_optical", restoreState: Bool = false) throws {
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
        sessionStartedAt = now
        heartRateReadingCount = 0
        frameCount = 0
        byteCount = 0
        reassembledFrameCount = 0
        validCrcFrameCount = 0
        recentHeartRate = HeartRateWindow(span: recentHeartRate.span)
        packetTypeCounts = PacketTypeCounts()
        deviceMetadataStrings = []
        lastR10Candidate = nil
        hrCrossCheckDiffBpm = nil
        lastWatermarkAt = nil
        sentSafeSequence = false
        reassembler = FrameReassembler()
        connection.start(restoreState: restoreState)
    }

    func stopSession(reason: String = "user_stopped") {
        guard let id = sessionID else { return }
        let frameCount = frameCount
        let byteCount = byteCount
        let dbPool = dbPool
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
            // Normalize immediately so the session is queryable the moment it
            // ends, rather than sitting as undecoded bytes until something else
            // happens to run. Ordered after the UPDATE above because the
            // normalizer reads `ended_at` to bound the session's frame window.
            _ = try? BleNormalizer.processPending(dbPool)
        }
        connection.disconnect()
        sessionID = nil
        sessionStartedAt = nil
    }

    /// Sends the safe, read-only-plus-live-stream sequence from docs/design.md's
    /// "What we stream": identity/battery first (to validate the envelope
    /// round-trips before trusting anything else), then the realtime toggles —
    /// HR, IMU, and optical (R21, the only source of true respiratory rate),
    /// all opcodes from the allowlist's live-only set. Called once from the UI
    /// when `connectionState == .ready`; harmless to call again, it's idempotent.
    ///
    /// Sequential and awaited, not fire-and-forget: sending all seven commands
    /// back-to-back with no wait lost the first two (HELLO, battery) in a real
    /// session — see `BandConnection.send`'s doc comment and
    /// docs/PROTOCOL-GEN5.md's "session 3". `commandResults` records which
    /// commands actually completed, for the UI to show.
    private(set) var commandResults: [(opcode: String, succeeded: Bool)] = []

    func beginSafeCommandSequence() async {
        guard !sentSafeSequence else { return }
        sentSafeSequence = true
        commandResults = []
        // getHelloHarvard/getBatteryLevel have never once gotten a response in
        // 6 sessions and 1327 command-response frames (docs/PROTOCOL-GEN5.md,
        // "session 5") — every one of the 5 opcodes below that DOES get
        // answered every time is sent with a 1-byte body; these two were the
        // only ones sent with an empty body. Testing the hypothesis that an
        // empty-body command is silently dropped by sending a harmless 0x00
        // byte instead of Data().
        let sequence: [(String, Ble.AllowedOpcode, Data)] = [
            ("getHelloHarvard", .getHelloHarvard, Data([0x00])),
            ("getBatteryLevel", .getBatteryLevel, Data([0x00])),
            ("toggleRealtimeHR", .toggleRealtimeHR, Data([0x01])),
            ("sendR10R11Realtime", .sendR10R11Realtime, Data([0x01])),
            ("toggleImuMode", .toggleImuMode, Data([0x01])),
            ("enableOpticalData", .enableOpticalData, Data([0x01])),
            ("toggleOpticalMode", .toggleOpticalMode, Data([0x01])),
        ]
        for (name, opcode, body) in sequence {
            do {
                try await connection.send(opcode: opcode, body: body)
                commandResults.append((name, true))
            } catch {
                commandResults.append((name, false))
            }
        }
    }

    /// Refreshes `ended_at` to the last moment we saw data, so a session killed
    /// mid-recording still has a real end time instead of NULL. `ended_reason`
    /// stays NULL until `stopSession` sets it — that is what distinguishes "the
    /// app was killed here" from "the user stopped it here".
    private func persistWatermarkIfDue(now: Date) {
        guard let id = sessionID else { return }
        if let last = lastWatermarkAt, now.timeIntervalSince(last) < Self.watermarkInterval { return }
        lastWatermarkAt = now

        let frameCount = frameCount
        let byteCount = byteCount
        let dbPool = dbPool
        Task {
            try? await dbPool.write { db in
                try db.execute(
                    sql: "UPDATE ble_sessions SET ended_at = ?, sample_count = ?, byte_count = ? WHERE id = ?",
                    arguments: [Int64(now.timeIntervalSince1970), frameCount, byteCount, id]
                )
            }
        }
    }

    private func handleRawFrame(characteristic: CBUUID, data: Data, receivedAt: Date) {
        frameCount += 1
        byteCount += data.count
        persistWatermarkIfDue(now: receivedAt)

        // Inbox-first: this write happens unconditionally, before any attempt
        // to interpret the bytes. A wrong envelope hypothesis below loses no
        // data — it only fails to light up the "confirmed" indicator.
        Task {
            try? await dbPool.write { db in
                try IngestInbox.append(db, source: .ble, kind: characteristic.uuidString, payload: data, receivedAt: receivedAt)
            }
        }

        // fd4b0007 is not Gen5Envelope-framed (docs/PROTOCOL-GEN5.md:
        // "these do not match the Gen5Envelope structure at all") — decode it
        // directly rather than handing it to the envelope reassembler, which
        // would just fail to find a marker and drop it.
        if characteristic == Ble.unknown0007CharacteristicUUID {
            for string in DeviceMetadataDecoder.extractStrings(raw: data) where !deviceMetadataStrings.contains(string) {
                deviceMetadataStrings.append(string)
            }
            return
        }

        for frame in reassembler.feed(data) {
            reassembledFrameCount += 1
            guard frame.headerCrcValid, frame.trailerCrcValid else { continue }
            validCrcFrameCount += 1
            if let packetType = frame.inner.first {
                packetTypeCounts.record(packetType)
            }
            if let bpm = RealtimeHRDecoder.heartRateBpm(inner: frame.inner) {
                lastHeartRateBpm = bpm
                heartRateReadingCount += 1
                recentHeartRate.append(bpm: Int(bpm), at: receivedAt)
                if let candidate = lastR10Candidate {
                    hrCrossCheckDiffBpm = Int(bpm) - Int(candidate.candidateHrBpm)
                }
            }
            if let candidate = R10Decoder.decode(inner: frame.inner) {
                lastR10Candidate = candidate
                if let bpm = lastHeartRateBpm {
                    hrCrossCheckDiffBpm = Int(bpm) - Int(candidate.candidateHrBpm)
                }
            }
        }
    }
}
