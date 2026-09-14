import SwiftUI

/// The day's strain on WHOOP's 0–21 scale, with its band.
struct StrainRow: View {
    let strain: Double?
    /// The scores belong to this morning.
    let isToday: Bool
    /// The day's cycle is still open, so the strain is a running total.
    let isInProgress: Bool

    @Environment(\.temperatureUnit) private var temperature

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AdaptiveRow(alignment: .firstTextBaseline) {
                Text(isToday && isInProgress ? "Strain today" : "Strain")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            } trailing: {
                if let strain {
                    Text("\(Text(Metric.strain.formatted(strain, temperature: temperature)).font(.display(.title))) \(Text(detail(for: strain)).font(.subheadline).foregroundStyle(.secondary))")
                } else {
                    Text("Not scored yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if let strain {
                StrainScale(strain: strain)
            }
        }
        .padding(.vertical, 4)
    }

    private func detail(for strain: Double) -> String {
        let band = StrainBand(strain: strain).label.lowercased()
        let maximum = StrainBand.scaleMaximum.formatted()
        return isInProgress ? "of \(maximum) · \(band) so far" : "of \(maximum) · \(band)"
    }
}
