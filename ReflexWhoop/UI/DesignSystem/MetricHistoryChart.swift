import Charts
import SwiftUI

/// A metric over time against its normal band. Every day with a value gets a
/// dot; unusual days are sunstone and larger, and the latest day is ringed.
struct MetricHistoryChart: View {
    let points: [MetricPoint]
    let metric: Metric

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Chart {
            NormalBandMarks(points: points, isContrastIncreased: contrast == .increased)
            GappedLineMarks(samples: points, maximumGap: MetricPoint.maximumGap, time: \.date, value: \.value, valueLabel: metric.label)
                .foregroundStyle(.primary)
                .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            ForEach(points) { point in
                PointMark(x: .value("Day", point.date), y: .value(metric.label, point.value))
                    .symbol {
                        DayDot(isUnusual: point.status.isUnusual, isLatest: point == points.last)
                    }
            }
        }
        .chartYScale(domain: ChartDomain.padded(points) ?? 0...1)
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
        .accessibilityChartDescriptor(MetricHistoryChartDescriptor(points: points, metric: metric))
    }
}
