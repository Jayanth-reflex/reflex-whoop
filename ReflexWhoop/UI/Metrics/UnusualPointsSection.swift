import SwiftUI

/// The days in the range that were unusual for this metric, newest first.
struct UnusualPointsSection: View {
    let metric: Metric
    let points: [MetricPoint]

    @Environment(\.temperatureUnit) private var temperature

    var body: some View {
        if !points.isEmpty {
            Section {
                ForEach(points.reversed()) { point in
                    LabeledContent {
                        Text("\(value(of: point)) · \(point.status.label.lowercased())")
                            .foregroundStyle(Color.sunstone)
                    } label: {
                        Text(point.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                    }
                }
            } header: {
                SectionHeader(title: metric.section == .overnight ? "Unusual nights" : "Unusual days")
            }
        }
    }

    /// A metric read as its change from normal shows that change.
    private func value(of point: MetricPoint) -> String {
        if metric.leadsWithDifferenceFromNormal, let range = point.range {
            metric.formattedDifferenceWithUnit(point.value, from: range, temperature: temperature)
        } else {
            metric.formattedWithUnit(point.value, temperature: temperature)
        }
    }
}
