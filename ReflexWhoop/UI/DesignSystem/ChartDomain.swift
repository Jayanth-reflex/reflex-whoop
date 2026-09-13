import Foundation

/// Y-axis domains for the app's charts. Set explicitly because Swift Charts'
/// automatic domain starts at zero, which flattens a heart rate or HRV line.
enum ChartDomain {
    /// The smallest range holding every value, widened on each side by
    /// `fraction` of its span (or by 1 when every value is equal) so marks at
    /// the extremes aren't clipped.
    static func padded(_ values: [Double], fraction: Double = 0.08) -> ClosedRange<Double>? {
        guard let lowest = values.min(), let highest = values.max() else { return nil }
        let padding = highest > lowest ? (highest - lowest) * fraction : 1
        return (lowest - padding)...(highest + padding)
    }

    /// Covers each point's value and its normal band.
    static func padded(_ points: [MetricPoint], fraction: Double = 0.08) -> ClosedRange<Double>? {
        padded(points.flatMap { point in
            [point.value] + (point.range.map { [$0.lowerBound, $0.upperBound] } ?? [])
        }, fraction: fraction)
    }
}
