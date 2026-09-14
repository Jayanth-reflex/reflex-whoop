import SwiftUI

/// The latest value large, its date, and in words where it sits against the
/// person's normal when the metric has one.
struct MetricDetailHeader: View {
    let metric: Metric
    let point: MetricPoint

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(point.date, format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            HeroValue(metric.formatted(point.value), unit: metric.unit.isEmpty ? nil : metric.unit, scale: 1.9)
            if let statusSentence = point.statusSentence(for: metric) {
                Text(statusSentence)
                    .foregroundStyle(point.status.isUnusual ? AnyShapeStyle(Color.sunstone) : AnyShapeStyle(.primary))
            }
        }
        .accessibilityElement(children: .combine)
    }
}
