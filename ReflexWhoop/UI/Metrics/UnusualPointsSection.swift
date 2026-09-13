import SwiftUI

/// The days in the range that were unusual for this metric, newest first.
struct UnusualPointsSection: View {
    let metric: Metric
    let points: [MetricPoint]

    var body: some View {
        if !points.isEmpty {
            Section {
                ForEach(points.reversed()) { point in
                    LabeledContent {
                        Text("\(metric.formattedWithUnit(point.value)) · \(point.status.label.lowercased())")
                            .foregroundStyle(Color.sunstone)
                    } label: {
                        Text(point.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated).recordedDay())
                    }
                }
            } header: {
                SectionHeader(title: metric.section == .overnight ? "Unusual nights" : "Unusual days")
            }
        }
    }
}
