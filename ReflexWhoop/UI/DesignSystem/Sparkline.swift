import Charts
import SwiftUI

/// A metric's history at row size: the normal band, the line, and the latest
/// day emphasised. Hidden from VoiceOver: the row states the value.
struct Sparkline: View {
    let points: [MetricPoint]

    var body: some View {
        Chart {
            NormalBandMarks(points: points)
            GappedLineMarks(samples: points, maximumGap: MetricPoint.maximumGap, time: \.date, value: \.value, valueLabel: "Value")
                .foregroundStyle(.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            if let latest = points.last {
                PointMark(x: .value("Day", latest.date), y: .value("Value", latest.value))
                    .foregroundStyle(.primary)
                    .symbolSize(36)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: ChartDomain.padded(points) ?? 0...1)
        .accessibilityHidden(true)
    }
}
