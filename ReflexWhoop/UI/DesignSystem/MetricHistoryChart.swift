import Charts
import SwiftUI

/// A metric over time against its normal band, in the unit it's shown in.
/// Every day with a value gets a dot; unusual days are sunstone and larger,
/// and the latest day is ringed.
struct MetricHistoryChart: View {
    let points: [MetricPoint]
    let metric: Metric

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.temperatureUnit) private var temperature

    var body: some View {
        let shown = points.map { $0.displayed(for: metric, temperature: temperature) }
        Chart {
            NormalBandMarks(points: shown, isContrastIncreased: contrast == .increased)
            GappedLineMarks(samples: shown, maximumGap: MetricPoint.maximumGap, time: \.date, value: \.value, valueLabel: metric.label)
                .foregroundStyle(.primary)
                .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            ForEach(shown) { point in
                PointMark(x: .value("Day", point.date), y: .value(metric.label, point.value))
                    .symbol {
                        DayDot(isUnusual: point.status.isUnusual, isLatest: point == shown.last)
                    }
            }
        }
        .chartYScale(domain: ChartDomain.padded(shown) ?? 0...1)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) {
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) {
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
        .accessibilityChartDescriptor(MetricHistoryChartDescriptor(points: shown, metric: metric, temperature: temperature))
    }
}
