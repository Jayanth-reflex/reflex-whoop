import SwiftUI

/// The history chart with its key, and the range's average, spread and count.
struct MetricHistoryCard: View {
    let metric: Metric
    let points: [MetricPoint]
    let summary: MetricHistorySummary

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.temperatureUnit) private var temperature

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MetricHistoryChart(points: points, metric: metric)
                .frame(height: 210)

            // Without a normal range there's no band to key, and no day can be unusual.
            if metric.hasNormalRange {
                HStack(spacing: 14) {
                    Label {
                        Text("Your normal")
                    } icon: {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(contrast == .increased ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.quaternary))
                            .frame(width: 16, height: 8)
                    }
                    StatusLabel(text: metric.section == .overnight ? "Unusual night" : "Unusual day", tint: Color.sunstone)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            }

            Divider()

            StatRow {
                StatValue(title: "Average", value: metric.formatted(summary.average, temperature: temperature), unit: metric.unit(temperature))
                StatValue(title: "Range", value: "\(metric.formatted(summary.lowest, temperature: temperature))–\(metric.formatted(summary.highest, temperature: temperature))", unit: metric.unit(temperature))
                StatValue(title: metric.periodNoun, value: summary.count.formatted())
            }
        }
        .padding(.vertical, 8)
    }
}
