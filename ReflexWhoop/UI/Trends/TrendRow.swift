import SwiftUI

/// A metric's latest value in the range beside a sparkline of the range.
struct TrendRow: View {
    let metric: Metric
    let points: [MetricPoint]

    var body: some View {
        AdaptiveRow {
            VStack(alignment: .leading, spacing: 2) {
                Text(metric.label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                MetricValueText(metric: metric, value: points.last?.value)
                    .font(.title2)
            }
        } trailing: {
            Sparkline(points: points)
                .frame(width: 104, height: 34)
                .opacity(points.count > 1 ? 1 : 0)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
