import SwiftUI

/// The history chart with its key, and the range's average, spread and count.
struct MetricHistoryCard: View {
    let metric: Metric
    let points: [MetricPoint]
    let summary: MetricHistorySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MetricHistoryChart(points: points, metric: metric)
                .frame(height: 210)

            HStack(spacing: 14) {
                if metric.hasNormalRange {
                    Label {
                        Text("Your normal")
                    } icon: {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.quaternary)
                            .frame(width: 16, height: 8)
                    }
                }
                StatusLabel(text: metric.section == .overnight ? "Unusual night" : "Unusual day", tint: Color.sunstone)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)

            Divider()

            HStack(alignment: .top) {
                StatValue(title: "Average", value: metric.formatted(summary.average), unit: metric.unit)
                    .frame(maxWidth: .infinity, alignment: .leading)
                StatValue(title: "Range", value: "\(metric.formatted(summary.lowest))–\(metric.formatted(summary.highest))", unit: metric.unit)
                    .frame(maxWidth: .infinity, alignment: .leading)
                StatValue(title: metric.periodNoun, value: summary.count.formatted())
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 8)
    }
}
