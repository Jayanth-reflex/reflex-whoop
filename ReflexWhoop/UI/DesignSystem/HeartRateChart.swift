import Charts
import SwiftUI

/// Heart rate over real time, with the line broken wherever readings stop
/// for longer than `maximumGap`.
struct HeartRateChart: View {
    let readings: [HeartRateReading]
    let maximumGap: TimeInterval

    var body: some View {
        Chart {
            GappedLineMarks(
                samples: readings,
                maximumGap: maximumGap,
                time: \.time,
                value: \.bpm,
                valueLabel: "Heart rate",
                areaFloor: domain.lowerBound
            )
            .foregroundStyle(Color.roseQuartz)
            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .chartYScale(domain: domain)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) {
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) {
                AxisValueLabel(format: .dateTime.hour().minute())
            }
        }
        .accessibilityLabel("Heart rate")
        .accessibilityValue(rangeDescription)
    }

    private var bpm: [Double] { readings.map(\.bpm) }

    private var domain: ClosedRange<Double> {
        ChartDomain.padded(bpm) ?? 50...100
    }

    private var rangeDescription: String {
        guard let lowest = bpm.min(), let highest = bpm.max() else { return "No readings" }
        return "\(lowest.formatted(.number.precision(.fractionLength(0))))–\(highest.formatted(.number.precision(.fractionLength(0)))) bpm"
    }
}
