import Foundation

/// How stale each resource is allowed to get before a foreground sync bothers
/// re-fetching it. Keeps a typical "app opened" sync to a handful of requests
/// instead of always re-pulling everything — per docs/ARCHITECTURE.md's
/// Source A section.
enum SyncPolicy {
    static let stalenessBudget: [String: TimeInterval] = [
        "workout": 30 * 60,
        "sleep": 60 * 60,
        "recovery": 60 * 60,
        "cycle": 4 * 60 * 60,
        "profile": 24 * 60 * 60,
        "body_measurement": 24 * 60 * 60,
    ]

    static func isStale(resource: String, lastSyncedAt: Date?) -> Bool {
        guard let lastSyncedAt else { return true }
        let budget = stalenessBudget[resource] ?? 60 * 60
        return Date().timeIntervalSince(lastSyncedAt) >= budget
    }

    /// How far back an incremental sync re-pulls, even for a resource that was
    /// synced recently — because WHOOP re-scores sleep and recovery retroactively.
    /// Content-hash change detection (`RecordDAO`) makes this overlap nearly free:
    /// unchanged records are a hash comparison, not a write.
    static let rescoreLookback: TimeInterval = 7 * 24 * 60 * 60
}
