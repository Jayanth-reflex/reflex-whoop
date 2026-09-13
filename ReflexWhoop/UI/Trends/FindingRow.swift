import SwiftUI

/// A moderate or strong result, with its direction and the numbers behind it.
struct FindingRow: View {
    let row: CorrelationRow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(PredictorLabel.label(row.predictor))
            Text(row.rho > 0 ? "Higher values go with better recovery the next morning." : "Higher values go with worse recovery the next morning.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(statistics)
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var statistics: String {
        let parts = ["r \(StatisticFormat.r(row.rho))", row.pValueBhCorrected.map { "p \(StatisticFormat.p($0))" }, "\(row.n) days"]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }
}
