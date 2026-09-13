import Foundation

/// One day's value for a metric, with that day's normal range when one exists.
struct MetricPoint: Identifiable, Equatable {
    /// Neighbouring points further apart than this have a day with no value
    /// between them. Longer than 24 hours to allow for clock changes.
    static let maximumGap: TimeInterval = 1.5 * 86_400

    let day: String
    let date: Date
    let value: Double
    let range: NormalRange?

    var id: String { day }

    var status: ReadingStatus {
        .classify(value, against: range)
    }
}
