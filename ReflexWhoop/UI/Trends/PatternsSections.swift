import SwiftUI

/// Patterns' results: findings with a direction, weak results without one,
/// and predictors still collecting days.
struct PatternsSections: View {
    let summary: PatternsSummary

    var body: some View {
        if !summary.findings.isEmpty {
            Section {
                ForEach(summary.findings) { row in
                    FindingRow(row: row)
                }
            } header: {
                SectionHeader(title: "Worth a closer look")
            } footer: {
                SectionFooter(text: "Moving together isn't proof that one causes the other.")
            }
        }

        if !summary.weak.isEmpty {
            Section {
                ForEach(summary.weak) { row in
                    LabeledContent(PredictorLabel.label(row.predictor)) {
                        Text("r \(StatisticFormat.r(row.rho))")
                            .monospacedDigit()
                    }
                }
            } header: {
                SectionHeader(title: summary.findings.isEmpty ? "Closest so far" : "Too weak to call")
            } footer: {
                SectionFooter(text: weakFooter)
            }

            if summary.findings.isEmpty {
                Section {
                    Text("With numbers this close to zero, \u{201C}more helps\u{201D} and \u{201C}more hurts\u{201D} are equally likely to be noise, so neither is claimed. Real patterns in one person's data usually take a few months to show, and even then moving together isn't cause.")
                } header: {
                    SectionHeader(title: "Why no direction is shown")
                }
            }
        }

        if !summary.building.isEmpty {
            Section {
                ForEach(summary.building) { row in
                    BuildingRow(row: row)
                }
            } header: {
                SectionHeader(title: "Not enough days yet")
            } footer: {
                SectionFooter(text: "Each needs \(Stats.minimumDaysForStrength) days with a value before it can be compared.")
            }
        }
    }

    private var weakFooter: String {
        let scale = "The number is r, which runs from −1 to +1, where 0 means no relationship."
        guard let p = summary.lowestWeakPValue else { return scale }
        let testing = "After allowing for testing \(summary.comparedCount) things at once, the lowest p is \(StatisticFormat.p(p))"
        return p >= 0.05
            ? "\(scale) \(testing): about what you'd expect if none of them had anything to do with your recovery."
            : "\(scale) \(testing), so some may be more than chance, but all are too weak to act on."
    }
}
