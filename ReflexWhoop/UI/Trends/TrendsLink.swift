import Foundation

/// Trends' destinations other than a metric.
enum TrendsLink: Hashable {
    case patterns
    case unusualDays(HistoryRange)
}
