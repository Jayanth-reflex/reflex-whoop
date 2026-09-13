import Foundation

/// Everything Today reads in one load.
struct TodayContent {
    let snapshot: TodaySnapshot?
    let sources: AppContainer.SourceSnapshot
    let heartRateToday: HeartRateSpan

    var layout: TodayLayout {
        .choose(hasScores: snapshot != nil, whoop: sources.whoop, hasBandHistory: sources.archive.bleSessionCount > 0)
    }
}
