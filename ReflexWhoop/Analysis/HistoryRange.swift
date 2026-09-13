import Foundation

/// The spans Trends offers. A span of N days includes today as day one.
enum HistoryRange: String, CaseIterable, Identifiable {
    case thirtyDays, ninetyDays, year, all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .thirtyDays: "30D"
        case .ninetyDays: "90D"
        case .year: "1Y"
        case .all: "All"
        }
    }

    var title: String {
        switch self {
        case .thirtyDays: "Last 30 days"
        case .ninetyDays: "Last 90 days"
        case .year: "Last year"
        case .all: "All history"
        }
    }

    /// Ends a count: "4 unusual days in the last 30 days".
    var withinPhrase: String {
        switch self {
        case .thirtyDays: "in the last 30 days"
        case .ninetyDays: "in the last 90 days"
        case .year: "in the last year"
        case .all: "in all your history"
        }
    }

    var days: Int? {
        switch self {
        case .thirtyDays: 30
        case .ninetyDays: 90
        case .year: 365
        case .all: nil
        }
    }

    /// First `yyyy-MM-dd` day to include, or `nil` for all history.
    func firstDay(endingOn now: Date) -> String? {
        days.map { RecordDAO.dayString(for: now.addingTimeInterval(-Double($0 - 1) * 86_400)) }
    }
}
