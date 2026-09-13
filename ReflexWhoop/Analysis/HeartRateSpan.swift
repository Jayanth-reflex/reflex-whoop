import Foundation

/// Band heart rate across a stretch of time, from one-minute rollups: a
/// reading per minute that has any, plus the stretch's statistics. The
/// statistics are `nil` when nothing was recorded.
struct HeartRateSpan: Equatable {
    let readings: [HeartRateReading]
    /// Weighted by how many raw readings each minute holds.
    let averageBpm: Double?
    let lowestBpm: Double?
    let highestBpm: Double?
}
