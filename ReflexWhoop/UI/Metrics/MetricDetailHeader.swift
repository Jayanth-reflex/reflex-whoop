import SwiftUI

/// The latest value large, its date, and in words where it sits against the
/// person's normal.
struct MetricDetailHeader: View {
    let metric: Metric
    let point: MetricPoint

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(point.date, format: .dateTime.weekday(.wide).day().month(.wide).recordedDay())
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            HeroValue(metric.formatted(point.value), unit: metric.unit.isEmpty ? nil : metric.unit, scale: 1.9)
            Text(statusSentence)
                .foregroundStyle(point.status.isUnusual ? AnyShapeStyle(Color.sunstone) : AnyShapeStyle(.primary))
        }
        .accessibilityElement(children: .combine)
    }

    private var statusSentence: String {
        let status = point.status
        guard let range = point.range else { return status.label }
        let usual = "\(metric.formatted(range.lowerBound))–\(metric.formattedWithUnit(range.upperBound))"
        return switch status {
        case .within, .above, .below: "\(status.label) of \(usual)"
        case .unusuallyHigh, .unusuallyLow: "\(status.label). Your normal is \(usual)"
        case .noReading, .notEnoughHistory: status.label
        }
    }
}
