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

    /// What `.empty` says, from where the WHOOP account stands. Connected but
    /// not yet synced is waiting, not missing.
    static func emptyDescription(whoop: SourceState) -> String {
        switch whoop {
        case .notConfigured: "Connect your WHOOP account in Archive, or record from your band."
        case .active, .unreachable: "Your WHOOP history appears here as soon as it arrives."
        case .unauthorized: "Sign in to your WHOOP account in Archive, or record from your band."
        case .inactive: "WHOOP isn't sending new data. Record from your band to see your heart rate here."
        }
    }
}
