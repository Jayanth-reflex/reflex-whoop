import Foundation

/// Which version of Today to show.
enum TodayLayout: Equatable {
    /// WHOOP's scores for the latest day it scored.
    case scores
    /// Heart rate from the band. After a membership ends this replaces the
    /// scores, so the last scored day is never presented as today.
    case band(membershipEnded: Bool)
    /// Nothing held yet.
    case empty

    static func choose(hasScores: Bool, whoop: SourceState, hasBandHistory: Bool) -> TodayLayout {
        if case .inactive = whoop {
            return hasScores || hasBandHistory ? .band(membershipEnded: true) : .empty
        }
        if hasScores { return .scores }
        return hasBandHistory ? .band(membershipEnded: false) : .empty
    }
}
