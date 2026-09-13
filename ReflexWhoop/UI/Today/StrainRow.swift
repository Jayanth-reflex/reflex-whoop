import SwiftUI

/// The day's strain on WHOOP's 0–21 scale, with its band.
struct StrainRow: View {
    let strain: Double?
    /// The day is still going, so the strain is a running total.
    let isToday: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(isToday ? "Strain today" : "Strain")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let strain {
                    Text("\(Text(Metric.strain.formatted(strain)).font(.display(.title))) \(Text(detail(for: strain)).font(.subheadline).foregroundStyle(.secondary))")
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
        return isToday ? "of \(maximum) · \(band) so far" : "of \(maximum) · \(band)"
    }
}
