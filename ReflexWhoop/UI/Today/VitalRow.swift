import SwiftUI

/// One overnight vital: its value, where that sits against the person's
/// normal in words, and the same as a range strip. A vital read as its change
/// from normal leads with that change and names the reading beside its status.
struct VitalRow: View {
    let metric: Metric
    let value: Double?
    let range: NormalRange?

    @Environment(\.temperatureUnit) private var temperature

    private var status: ReadingStatus {
        .classify(value, against: range)
    }

    var body: some View {
        AdaptiveRow {
            VStack(alignment: .leading, spacing: 4) {
                Text(metric.label)
                Text(statusText)
                    .font(.footnote)
                    .bold(status.isUnusual)
                    .foregroundStyle(status.foreground)
            }
        } trailing: {
            TrailingStack {
                MetricValueText(metric: metric, value: value, range: range)
                RangeStrip(value: value, range: range)
                    .frame(width: 118)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityValue(usualRangeDescription)
    }

    private var statusText: String {
        guard let value else { return "No reading that night" }
        guard metric.leadsWithDifferenceFromNormal, range != nil else { return status.label }
        return "\(status.label) · \(metric.formattedWithUnit(value, temperature: temperature))"
    }

    private var usualRangeDescription: String {
        guard let range else { return "" }
        return "Your normal is \(metric.formatted(range.lowerBound, temperature: temperature)) to \(metric.formattedWithUnit(range.upperBound, temperature: temperature))"
    }
}
