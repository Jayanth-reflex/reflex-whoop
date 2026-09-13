import Foundation

extension Date.FormatStyle {
    /// For dates that stand for a stored `yyyy-MM-dd` day, which is midnight
    /// UTC (`RecordDAO.date(forDay:)`). Formats in UTC so the day shown never
    /// slips to the previous one in time zones west of UTC.
    func recordedDay() -> Date.FormatStyle {
        var style = self
        style.timeZone = .gmt
        return style
    }
}
