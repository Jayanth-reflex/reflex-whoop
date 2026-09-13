import Foundation

/// A day `AnomalyEngine` flagged, with each flagged reading.
struct UnusualDay: Identifiable {
    let day: String
    let date: Date
    let isPossibleIllness: Bool
    let readings: [UnusualReading]

    var id: String { day }
}
