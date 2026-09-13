import SwiftUI

/// A past recording: when it started, how long it ran, and its average.
struct RecordingRow: View {
    let recording: RecordingSummary

    var body: some View {
        LabeledContent {
            if let average = recording.averageBpm {
                Text("\(average.formatted(.number.precision(.fractionLength(0)))) bpm avg")
                    .monospacedDigit()
            }
        } label: {
            SubtitledRow(title: RecordingFormat.start(recording.startedAt), subtitle: RecordingFormat.length(of: recording))
        }
    }
}
