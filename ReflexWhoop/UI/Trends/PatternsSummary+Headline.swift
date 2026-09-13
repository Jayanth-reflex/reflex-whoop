import Foundation

extension PatternsSummary {
    /// The one-line answer, used as Patterns' title and on Trends' row.
    var headline: String {
        switch findings.count {
        case 0 where comparedCount == 0: "Not enough days yet"
        case 0: "Nothing stands out yet"
        case 1: "1 possible pattern"
        case let count: "\(count) possible patterns"
        }
    }
}
