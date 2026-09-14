import Foundation

/// How recordings are named and measured on screen.
enum RecordingFormat {
    /// "Today, 2:11 PM", "Yesterday, 7:53 PM", or "Wed 10 Sep, 6:13 PM".
    static func start(_ date: Date, calendar: Calendar = .current, now: Date = .now, locale: Locale = .current) -> String {
        let time = date.formatted(Date.FormatStyle(timeZone: calendar.timeZone).hour().minute().locale(locale))
        return switch calendar.relativeDay(of: date, now: now) {
        case .today: "Today, \(time)"
        case .yesterday: "Yesterday, \(time)"
        case nil: "\(date.formatted(Date.FormatStyle(timeZone: calendar.timeZone).weekday(.abbreviated).day().month(.abbreviated).locale(locale))), \(time)"
        }
    }

    /// First to last reading, or why there's no length.
    static func length(of recording: RecordingSummary) -> String {
        guard let span = recording.span else { return "Nothing captured" }
        guard span >= 60 else { return "Under a minute" }
        return Duration.seconds(span).formatted(.hoursMinutes)
    }
}
