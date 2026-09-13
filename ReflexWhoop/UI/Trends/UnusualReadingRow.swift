import SwiftUI

/// A reading that was unusual, beside the normal it was judged against.
struct UnusualReadingRow: View {
    let reading: UnusualReading

    var body: some View {
        AdaptiveRow(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(reading.metric.label)
                Text("Usually \(reading.metric.formatted(reading.range.lowerBound))–\(reading.metric.formattedWithUnit(reading.range.upperBound))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } trailing: {
            TrailingStack(spacing: 2) {
                MetricValueText(metric: reading.metric, value: reading.value)
                Text(reading.status.label)
                    .font(.footnote)
                    .bold()
                    .foregroundStyle(reading.status.foreground)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
