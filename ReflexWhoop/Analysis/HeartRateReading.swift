import Foundation

/// A heart-rate value at a moment: a live reading, or a one-minute average
/// from a recording.
struct HeartRateReading: Identifiable, Equatable {
    let time: Date
    let bpm: Double

    var id: Date { time }
}
