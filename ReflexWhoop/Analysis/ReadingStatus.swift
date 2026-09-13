import Foundation

/// Where a reading sits relative to the person's own normal. Deliberately
/// neutral about direction: above normal is not automatically good.
enum ReadingStatus: Equatable {
    case within, above, below, unusuallyHigh, unusuallyLow, noReading, notEnoughHistory

    static func classify(_ value: Double?, against range: NormalRange?) -> ReadingStatus {
        guard let value else { return .noReading }
        guard let range, let z = range.zScore(of: value) else { return .notEnoughHistory }
        let unusual = AnomalyEngine.singleMetricThreshold
        return switch z {
        case unusual...: .unusuallyHigh
        case ...(-unusual): .unusuallyLow
        case 1...: .above
        case ...(-1): .below
        default: .within
        }
    }

    var isUnusual: Bool { self == .unusuallyHigh || self == .unusuallyLow }

    var label: String {
        switch self {
        case .within: "Within your normal"
        case .above: "Above your normal"
        case .below: "Below your normal"
        case .unusuallyHigh: "Unusually high"
        case .unusuallyLow: "Unusually low"
        case .noReading: "No reading"
        case .notEnoughHistory: "Not enough history yet"
        }
    }
}
