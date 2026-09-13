import SwiftUI

/// A predictor still collecting the days it needs before it can be compared.
struct BuildingRow: View {
    let row: CorrelationRow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent(PredictorLabel.label(row.predictor)) {
                Text("\(min(row.n, Stats.minimumDaysForStrength)) of \(Stats.minimumDaysForStrength) days")
                    .monospacedDigit()
            }
            ProgressView(value: Double(min(row.n, Stats.minimumDaysForStrength)), total: Double(Stats.minimumDaysForStrength))
                .tint(.secondary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 2)
    }
}
