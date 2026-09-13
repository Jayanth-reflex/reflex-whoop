import SwiftUI

/// One overnight vital: its value, where that sits against the person's
/// normal in words, and the same as a range strip.
struct VitalRow: View {
    let metric: Metric
    let value: Double?
    let range: NormalRange?

    private var status: ReadingStatus {
        .classify(value, against: range)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(metric.label)
                Text(status == .noReading ? "No reading that night" : status.label)
                    .font(.footnote)
                    .bold(status.isUnusual)
                    .foregroundStyle(status.foreground)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                MetricValueText(metric: metric, value: value)
                RangeStrip(value: value, range: range)
                    .frame(width: 118)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityValue(usualRangeDescription)
    }

    private var usualRangeDescription: String {
        guard let range else { return "" }
        return "Your normal is \(metric.formatted(range.lowerBound)) to \(metric.formatted(range.upperBound)) \(metric.unit)"
    }
}
