import Charts
import SwiftUI

/// A line through time-ordered samples that breaks wherever neighbours are
/// more than `maximumGap` apart, so a stretch with no readings is drawn as
/// nothing rather than as a straight line that looks like data. With an
/// `areaFloor`, each run also gets a faint fill down to it.
///
/// Style it from outside: `.foregroundStyle` and `.lineStyle` apply to every run.
struct GappedLineMarks<Sample: Identifiable>: ChartContent where Sample.ID: Plottable {
    let samples: [Sample]
    let maximumGap: TimeInterval
    let time: KeyPath<Sample, Date>
    let value: KeyPath<Sample, Double>
    let valueLabel: String
    var areaFloor: Double?

    var body: some ChartContent {
        ForEach(ContinuousRuns.split(samples, maximumGap: maximumGap, time: { $0[keyPath: time] }), id: \.first?.id) { run in
            ForEach(run) { sample in
                if let areaFloor {
                    AreaMark(
                        x: .value("Time", sample[keyPath: time]),
                        yStart: .value("Floor", areaFloor),
                        yEnd: .value(valueLabel, sample[keyPath: value]),
                        series: .value("Run", run[0].id)
                    )
                    .opacity(0.1)
                }
                LineMark(
                    x: .value("Time", sample[keyPath: time]),
                    y: .value(valueLabel, sample[keyPath: value]),
                    series: .value("Run", run[0].id)
                )
            }
        }
    }
}
