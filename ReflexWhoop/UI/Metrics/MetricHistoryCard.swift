import SwiftUI

/// The history chart with its key, and the range's average, spread and count.
struct MetricHistoryCard: View {
    let metric: Metric
    let points: [MetricPoint]
    let summary: MetricHistorySummary

    @Environment(\.colorSchemeContrast) private var contrast

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
                            .fill(contrast == .increased ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.quaternary))
                            .frame(width: 16, height: 8)
                    }
                }
                StatusLabel(text: metric.section == .overnight ? "Unusual night" : "Unusual day", tint: Color.sunstone)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)

            Divider()

            StatRow {
                StatValue(title: "Average", value: metric.formatted(summary.average), unit: metric.unit)
                StatValue(title: "Range", value: "\(metric.formatted(summary.lowest))–\(metric.formatted(summary.highest))", unit: metric.unit)
                StatValue(title: metric.periodNoun, value: summary.count.formatted())
            }
        }
        .padding(.vertical, 8)
    }
}
