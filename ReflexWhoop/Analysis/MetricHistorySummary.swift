import Foundation

/// Average, lowest, highest and count for a run of values. `nil` when there
/// are none, so an empty history is never summarised as zero.
struct MetricHistorySummary: Equatable {
    let average: Double
    let lowest: Double
    let highest: Double
    let count: Int

    init?(values: [Double]) {
        guard let lowest = values.min(), let highest = values.max() else { return nil }
        self.average = values.reduce(0, +) / Double(values.count)
        self.lowest = lowest
        self.highest = highest
        self.count = values.count
    }
}
