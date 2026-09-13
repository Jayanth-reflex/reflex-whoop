import SwiftUI

/// The one-sentence answer at the top of Patterns, and how it was reached.
struct PatternsHeadline: View {
    let summary: PatternsSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(summary.headline)
                .font(.display(.title))
            Text(detail)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        guard summary.comparedCount > 0 else {
            return "Each thing needs \(Stats.minimumDaysForStrength) days with a value before it can be compared with how recovered you were the next morning."
        }
        let compared = "We compared \(summary.comparedCount) things with how recovered you were the next morning, across \(summary.dayCount) days."
        guard summary.findings.isEmpty else { return compared }
        return "\(compared) None of them moved with your recovery clearly enough to call."
    }
}
