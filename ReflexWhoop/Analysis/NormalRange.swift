import Foundation

/// A person's usual range for one metric on one day: the mean and standard
/// deviation of the days before it, as `BaselineEngine` stores them.
///
/// Every range the app draws uses the window `AnomalyEngine` flags unusual days
/// against, so a reading can never look normal on one screen and be listed as
/// unusual on another.
struct NormalRange: Equatable {
    static let windowDays = AnomalyEngine.baselineWindow

    let mean: Double
    let standardDeviation: Double

    var lowerBound: Double { mean - standardDeviation }
    var upperBound: Double { mean + standardDeviation }

    /// `nil` when the history has no spread to measure against.
    func zScore(of value: Double) -> Double? {
        guard standardDeviation > 0 else { return nil }
        return (value - mean) / standardDeviation
    }
}
