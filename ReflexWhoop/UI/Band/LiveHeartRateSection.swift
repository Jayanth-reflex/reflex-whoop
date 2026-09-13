import SwiftUI

/// The current heart rate as it arrives, and the last 20 minutes of it.
struct LiveHeartRateSection: View {
    let recorder: SpikeRecorder

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "heart.fill")
                        .font(.title)
                        .foregroundStyle(Color.roseQuartz)
                        .accessibilityHidden(true)
                    if let bpm = recorder.lastHeartRateBpm {
                        HeroValue(bpm.formatted(), unit: "bpm")
                            .contentTransition(.numericText(value: Double(bpm)))
                            .animation(.snappy, value: bpm)
                    } else {
                        HeroValue("—", unit: nil)
                            .accessibilityLabel("Waiting for heart rate")
                    }
                }
                Text(recorder.lastHeartRateBpm == nil ? "Waiting for the first reading" : "Live from your band")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if recorder.recentHeartRate.readings.count > 1 {
                VStack(alignment: .leading, spacing: 8) {
                    AdaptiveRow {
                        Text("Last 20 minutes")
                            .font(.footnote.weight(.semibold))
                    } trailing: {
                        if let range = recorder.recentHeartRate.bpmRange {
                            Text("\(range.lowerBound.formatted())–\(range.upperBound.formatted()) bpm")
                                .font(.footnote)
                                .monospacedDigit()
                        }
                    }
                    .foregroundStyle(.secondary)

                    HeartRateChart(readings: recorder.recentHeartRate.readings, maximumGap: 10)
                        .frame(height: 150)
                }
                .padding()
                .background(Color.surface, in: .rect(cornerRadius: 24))
            }
        }
        .padding(.vertical, 4)
    }
}
