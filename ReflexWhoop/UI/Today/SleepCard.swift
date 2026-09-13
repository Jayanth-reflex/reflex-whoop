import SwiftUI

/// Time asleep, when it was, and the split between stages.
struct SleepCard: View {
    let sleep: LatestSleepDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                if let asleep = sleep.asleepMilli {
                    let duration = Text(Duration.milliseconds(asleep), format: .units(allowed: [.hours, .minutes], width: .narrow))
                        .font(.title.weight(.semibold))
                    Text("\(duration) \(Text("asleep").foregroundStyle(.secondary))")
                } else {
                    Text("No stage totals from WHOOP")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(sleep.interval.lowerBound, format: timeStyle) – \(sleep.interval.upperBound, format: .dateTime.hour().minute())")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if sleep.asleepMilli != nil {
                SleepStageBar(sleep: sleep)
                Text("Stage totals only. WHOOP doesn't share the order they happened in.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    /// Times alone for last night; with the weekday for anything older.
    private var timeStyle: Date.FormatStyle {
        sleep.isFromLastNight() ? .dateTime.hour().minute() : .dateTime.weekday(.abbreviated).hour().minute()
    }
}
