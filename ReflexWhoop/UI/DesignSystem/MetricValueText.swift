import SwiftUI

/// A metric's formatted value with its unit set smaller and quieter. A
/// missing value is a dash, read by VoiceOver as "No reading", never zero.
///
/// Given the normal `range`, a metric read as its change from normal shows
/// that change instead: "+0.5 °C".
struct MetricValueText: View {
    let metric: Metric
    let value: Double?
    var range: NormalRange?

    @Environment(\.temperatureUnit) private var temperature

    var body: some View {
        if let value {
            let unit = Text(metric.unitSuffix(temperature))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if metric.leadsWithDifferenceFromNormal, let range {
                Text("\(Text(metric.formattedDifference(value, from: range, temperature: temperature)).bold())\(unit)")
                    .accessibilityLabel("\(metric.formattedDifferenceWithUnit(value, from: range, temperature: temperature)) from your normal")
            } else {
                Text("\(Text(metric.formatted(value, temperature: temperature)).bold())\(unit)")
            }
        } else {
            Text(verbatim: "—")
                .foregroundStyle(.secondary)
                .accessibilityLabel("No reading")
        }
    }
}
