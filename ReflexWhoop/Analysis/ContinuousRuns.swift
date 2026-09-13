import Foundation

/// Splits time-ordered samples wherever neighbours are further apart than
/// `maximumGap`, so a chart breaks its line where there are no readings
/// instead of drawing a straight line that looks like data.
enum ContinuousRuns {
    static func split<Sample>(_ samples: [Sample], maximumGap: TimeInterval, time: (Sample) -> Date) -> [[Sample]] {
        var runs: [[Sample]] = []
        for sample in samples {
            if let previous = runs.last?.last, time(sample).timeIntervalSince(time(previous)) <= maximumGap {
                runs[runs.count - 1].append(sample)
            } else {
                runs.append([sample])
            }
        }
        return runs
    }
}
