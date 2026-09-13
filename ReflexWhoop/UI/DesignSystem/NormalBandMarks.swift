import Charts
import SwiftUI

/// The normal range behind a metric's line: each day's mean ± 1 SD, broken
/// wherever a day has no value or no range.
struct NormalBandMarks: ChartContent {
    let points: [MetricPoint]
    /// Stronger under Increase Contrast; chart content can't read the environment itself.
    var isContrastIncreased = false

    var body: some ChartContent {
        let ranged = points.filter { $0.range != nil }
        ForEach(ContinuousRuns.split(ranged, maximumGap: MetricPoint.maximumGap, time: \.date), id: \.first?.id) { run in
            ForEach(run) { point in
                if let range = point.range {
                    AreaMark(
                        x: .value("Day", point.date),
                        yStart: .value("Usual low", range.lowerBound),
                        yEnd: .value("Usual high", range.upperBound),
                        series: .value("Run", run[0].id)
                    )
                }
            }
        }
        .foregroundStyle(isContrastIncreased ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.quaternary))
    }
}
