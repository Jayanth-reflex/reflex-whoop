import Foundation

/// One band recording as the Band tab lists it.
struct RecordingSummary: Identifiable, Hashable {
    let id: String
    let startedAt: Date
    let firstReadingAt: Date?
    let lastReadingAt: Date?
    let minutesWithReadings: Int
    let readingCount: Int
    let averageBpm: Double?
    let lowestBpm: Int?
    let highestBpm: Int?

    /// First to last reading. `nil` when nothing was captured.
    var span: TimeInterval? {
        guard let firstReadingAt, let lastReadingAt else { return nil }
        return lastReadingAt.timeIntervalSince(firstReadingAt)
    }
}
