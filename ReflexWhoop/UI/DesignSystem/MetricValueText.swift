import SwiftUI

/// A metric's formatted value with its unit set smaller and quieter. A
/// missing value is a dash, read by VoiceOver as "No reading", never zero.
struct MetricValueText: View {
    let metric: Metric
    let value: Double?

    var body: some View {
        if let value {
            let number = Text(metric.formatted(value)).bold()
            let unit = Text(metric.unitSuffix)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("\(number)\(unit)")
        } else {
            Text(verbatim: "—")
                .foregroundStyle(.secondary)
                .accessibilityLabel("No reading")
        }
    }
}
