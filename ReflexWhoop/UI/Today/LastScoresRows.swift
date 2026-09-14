import SwiftUI

/// The last scores WHOOP sent, dated, so they read as history.
struct LastScoresRows: View {
    let snapshot: TodaySnapshot

    var body: some View {
        ForEach([Metric.recovery, .heartRateVariability]) { metric in
            LabeledContent(metric.shortLabel) {
                if let value = snapshot.value(of: metric) {
                    Text("Last: \(metric.formattedWithUnit(value)) on \(scoredDay)")
                } else {
                    Text("No score")
                }
            }
        }
        if let sleep = snapshot.sleep, let asleep = sleep.asleepMilli {
            LabeledContent("Sleep") {
                Text("Last: \(Duration.milliseconds(asleep), format: .hoursMinutes) on \(sleep.interval.upperBound, format: .dateTime.day().month(.abbreviated))")
            }
        }
    }

    private var scoredDay: String {
        snapshot.date?.formatted(.dateTime.day().month(.abbreviated)) ?? snapshot.metrics.day
    }
}
