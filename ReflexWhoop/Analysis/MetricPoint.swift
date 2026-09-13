import Foundation

/// One day's value for a metric, with that day's normal range when one exists.
struct MetricPoint: Identifiable, Equatable {
    let day: String
    let date: Date
    let value: Double
    let range: NormalRange?

    var id: String { day }

    var status: ReadingStatus {
        .classify(value, against: range)
    }
}
