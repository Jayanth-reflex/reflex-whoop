import Foundation

/// A reading `AnomalyEngine` flagged, with the range it was flagged against.
struct UnusualReading: Identifiable {
    let metric: Metric
    let value: Double
    let range: NormalRange

    var id: Metric { metric }

    var status: ReadingStatus {
        .classify(value, against: range)
    }
}
