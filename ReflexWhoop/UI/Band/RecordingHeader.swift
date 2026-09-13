import SwiftUI

/// A recording's date, its time span, and how much it captured.
struct RecordingHeader: View {
    let recording: RecordingSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(recording.startedAt, format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(timeSpan)
                .font(.display(.title))
                .fixedSize(horizontal: false, vertical: true)
            Text("\(RecordingFormat.length(of: recording)) · \(recording.readingCount.formatted()) readings")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var timeSpan: String {
        let time = Date.FormatStyle.dateTime.hour().minute()
        guard let first = recording.firstReadingAt, let last = recording.lastReadingAt else {
            return "Started \(recording.startedAt.formatted(time))"
        }
        return "\(first.formatted(time)) – \(last.formatted(time))"
    }
}
