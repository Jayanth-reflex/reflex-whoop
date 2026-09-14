import SwiftUI

/// The latest value large, its date, and in words where it sits against the
/// person's normal when the metric has one. A metric read as its change from
/// normal leads with that change, with the reading itself beneath.
struct MetricDetailHeader: View {
    let metric: Metric
    let point: MetricPoint

    @Environment(\.temperatureUnit) private var temperature

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(point.date, format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            if metric.leadsWithDifferenceFromNormal, let range = point.range {
                HeroValue(metric.formattedDifference(point.value, from: range, temperature: temperature), unit: metric.unit(temperature), scale: 1.9)
                    .accessibilityLabel("\(metric.formattedDifferenceWithUnit(point.value, from: range, temperature: temperature)) from your normal")
            } else {
                HeroValue(metric.formatted(point.value, temperature: temperature), unit: unit, scale: 1.9)
            }
            if let statusSentence = point.statusSentence(for: metric, temperature: temperature) {
                Text(statusSentence)
                    .foregroundStyle(point.status.isUnusual ? AnyShapeStyle(Color.sunstone) : AnyShapeStyle(.primary))
            }
            if metric.leadsWithDifferenceFromNormal, point.range != nil {
                Text("Measured \(metric.formattedWithUnit(point.value, temperature: temperature))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var unit: String? {
        let unit = metric.unit(temperature)
        return unit.isEmpty ? nil : unit
    }
}
