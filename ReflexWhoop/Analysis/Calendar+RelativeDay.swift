import Foundation

extension Calendar {
    enum RelativeDay {
        case today, yesterday
    }

    /// `.today` or `.yesterday` when `date` falls on one of them, else `nil`.
    func relativeDay(of date: Date, now: Date) -> RelativeDay? {
        if isDate(date, inSameDayAs: now) { return .today }
        guard let yesterday = self.date(byAdding: .day, value: -1, to: now), isDate(date, inSameDayAs: yesterday) else { return nil }
        return .yesterday
    }
}
