import Foundation

/// What Archive's About section explains.
enum AboutTopic: CaseIterable, Hashable {
    case scores, neverDoes

    var title: String {
        switch self {
        case .scores: "How scores are worked out"
        case .neverDoes: "What the app never does"
        }
    }

    var points: [String] {
        switch self {
        case .scores:
            [
                "Recovery, strain and sleep come from WHOOP, shown as WHOOP sends them.",
                "Your normal is your average over the previous \(NormalRange.windowDays) days, give or take the amount you usually vary.",
                "Unusual means more than twice that usual amount away from your normal.",
                "Heart rate from the band is read live, about once a second, and averaged by the minute for charts.",
                "Readiness isn't shown. One of its inputs from WHOOP doesn't mean what it first seemed to, so it stays hidden until it's rebuilt.",
            ]
        case .neverDoes:
            [
                "Change anything on the band: its settings, clock or alarms.",
                "Read the band's stored history. Only heart rate heard live is recorded.",
                "Delete anything it has collected.",
                "Send your data anywhere. It only talks to WHOOP, to sign in and bring in your history.",
            ]
        }
    }
}
