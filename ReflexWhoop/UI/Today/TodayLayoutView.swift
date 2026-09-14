import SwiftUI

/// Picks the version of Today that fits what's held.
struct TodayLayoutView: View {
    let content: TodayContent
    let message: String?

    var body: some View {
        switch content.layout {
        case .scores:
            if let snapshot = content.snapshot {
                TodayScoresList(snapshot: snapshot, whoop: content.sources.whoop, message: message)
            }
        case .band(let membershipEnded):
            TodayBandList(content: content, membershipEnded: membershipEnded, message: message)
        case .empty:
            ContentUnavailableView(
                "Nothing to show yet",
                systemImage: "sun.max",
                description: Text(TodayLayout.emptyDescription(whoop: content.sources.whoop)).foregroundStyle(.secondary)
            )
        }
    }
}
