import SwiftUI

/// Today's heart rate from the band: average, lowest and highest, and a chart
/// of the one-minute averages.
struct HeartRateTodayCard: View {
    let span: HeartRateSpan

    var body: some View {
        if let average = span.averageBpm, let lowest = span.lowestBpm, let highest = span.highestBpm {
            VStack(alignment: .leading, spacing: 12) {
                StatRow {
                    StatValue(title: "Average", value: average.formatted(.bpm), unit: "bpm")
                    StatValue(title: "Lowest", value: lowest.formatted(.bpm), unit: "bpm")
                    StatValue(title: "Highest", value: highest.formatted(.bpm), unit: "bpm")
                }
                HeartRateChart(readings: span.readings, maximumGap: 3 * 60)
                    .frame(height: 170)
                Text("One-minute averages. Breaks are minutes with no readings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        } else {
            ContentUnavailableView(
                "No heart rate yet today",
                systemImage: "heart",
                description: Text("Turn on Keep recording in Band to record from your band.").foregroundStyle(.secondary)
            )
        }
    }
}
