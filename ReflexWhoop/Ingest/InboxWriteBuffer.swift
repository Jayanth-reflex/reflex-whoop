import Foundation
import GRDB

/// Collects band frames and writes them to the inbox a batch at a time.
///
/// Frames used to be written one transaction each, about 100,000 a day. Each commit
/// rewrote whole pages of the table and its indexes through the WAL for an 83-byte
/// frame, and iOS flagged the app for dirtying 1 GB of flash in six hours. A 10-second
/// batch carries about 14 frames and writes roughly a ninth as much.
///
/// The cost is that a batch lives only in memory until it is written: a hard kill loses
/// at most `maxAge` of frames. `flush()` runs when a session stops and when the app goes
/// to the background, so an ordinary exit loses nothing.
///
/// Order is preserved across batches. Each flush's write waits for the previous one, so
/// frames reach the inbox in arrival order — `FrameReassembler` replays them by `seq`,
/// and a frame split across two notifications only reassembles if they stay in order.
@MainActor
final class InboxWriteBuffer {
    /// Frames lost because their batch could not be written. Recorded on the session as
    /// `dropped_count`; the per-frame writes this replaced discarded failures with `try?`.
    private(set) var failedFrameCount = 0

    private let dbPool: DatabasePool
    private let maxFrames: Int
    private let maxAge: TimeInterval

    private var pending: [Frame] = []
    private var lastWrite: Task<Void, Never>?
    private var ageDeadline: Task<Void, Never>?

    private struct Frame {
        let kind: String
        let payload: Data
        let receivedAt: Date
    }

    init(dbPool: DatabasePool, maxFrames: Int = 64, maxAge: TimeInterval = 10) {
        self.dbPool = dbPool
        self.maxFrames = maxFrames
        self.maxAge = maxAge
    }

    func append(kind: String, payload: Data, receivedAt: Date) {
        pending.append(Frame(kind: kind, payload: payload, receivedAt: receivedAt))
        if pending.count == 1 { scheduleAgeDeadline() }

        let oldest = pending[0].receivedAt
        if pending.count >= maxFrames || receivedAt.timeIntervalSince(oldest) >= maxAge {
            flush()
        }
    }

    /// Hands the pending frames to the database as one transaction. Taking the batch and
    /// chaining its write happen with no `await` between them, so nothing can reorder or
    /// double-write a batch.
    func flush() {
        ageDeadline?.cancel()
        ageDeadline = nil
        guard !pending.isEmpty else { return }

        let batch = pending
        pending = []
        let previous = lastWrite
        let dbPool = dbPool
        lastWrite = Task {
            await previous?.value
            do {
                try await dbPool.write { db in
                    for frame in batch {
                        try IngestInbox.append(db, source: .ble, kind: frame.kind, payload: frame.payload, receivedAt: frame.receivedAt)
                    }
                }
            } catch {
                failedFrameCount += batch.count
            }
        }
    }

    /// Waits until every batch handed off so far has been written or counted as failed.
    /// Frames still pending are not flushed — call `flush()` first for that.
    func drain() async {
        await lastWrite?.value
    }

    /// A slow trickle of frames never fills a batch, so the oldest frame's age sends it.
    /// While the app is suspended this waits; the next frame to arrive re-checks the age.
    private func scheduleAgeDeadline() {
        let maxAge = maxAge
        ageDeadline = Task { [weak self] in
            try? await Task.sleep(for: .seconds(maxAge))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }
}
