import Foundation

/// A day `AnomalyEngine` flagged, with each flagged reading.
struct UnusualDay: Identifiable {
    let day: String
    let date: Date
    /// Set when the day was flagged for possible illness: the signals that
    /// moved together, empty if they couldn't be read.
    let illnessSignals: [Metric]?
    let readings: [UnusualReading]

    var id: String { day }
}
