import Foundation

extension MetricPoint {
    /// This point in the unit it's shown in, for plotting. The value and its
    /// normal range convert together, so its status doesn't change.
    func displayed(for metric: Metric, temperature: TemperatureUnit) -> MetricPoint {
        func shown(_ value: Double) -> Double { metric.displayValue(value, temperature: temperature) }
        return MetricPoint(
            day: day,
            date: date,
            value: shown(value),
            range: range.map { NormalRange(mean: shown($0.mean), standardDeviation: shown($0.mean + $0.standardDeviation) - shown($0.mean)) }
        )
    }
}
