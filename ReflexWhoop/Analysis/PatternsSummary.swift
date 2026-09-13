import Foundation

/// The correlation results sorted the way Patterns presents them. Every row
/// is a predictor tested against next-morning recovery.
struct PatternsSummary {
    /// Moderate or strong, strongest first. Only these get a direction.
    let findings: [CorrelationRow]
    /// Too weak to say anything about direction, strongest first.
    let weak: [CorrelationRow]
    /// Fewer than 30 days so far, most days first.
    let building: [CorrelationRow]

    init(rows: [CorrelationRow]) {
        let tested = rows.filter { $0.strengthEnum != .insufficient }.sorted { abs($0.rho) > abs($1.rho) }
        findings = tested.filter { $0.strengthEnum != .weak }
        weak = tested.filter { $0.strengthEnum == .weak }
        building = rows.filter { $0.strengthEnum == .insufficient }.sorted { $0.n > $1.n }
    }

    /// How many predictors had enough days to be compared.
    var comparedCount: Int { findings.count + weak.count }

    /// The most days any compared predictor was tested across.
    var dayCount: Int { (findings + weak).map(\.n).max() ?? 0 }

    /// Multiple-testing-corrected: the most convincing of the weak results.
    var lowestWeakPValue: Double? { weak.compactMap(\.pValueBhCorrected).min() }
}
