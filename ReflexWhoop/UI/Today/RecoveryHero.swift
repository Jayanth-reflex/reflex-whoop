import SwiftUI

/// Today's headline: the recovery score, its band, what it means for the day,
/// and where it sits on WHOOP's scale against the person's usual range.
struct RecoveryHero: View {
    let score: Double?
    let usual: NormalRange?
    let isIllnessFlagged: Bool

    @Environment(\.temperatureUnit) private var temperature

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recovery")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if let score {
                let band = RecoveryBand(score: score)
                AdaptiveRow(alignment: .firstTextBaseline, spacing: 14, pinsTrailing: false) {
                    HeroValue(Metric.recovery.formatted(score, temperature: temperature), unit: Metric.recovery.unit(temperature))
                } trailing: {
                    StatusLabel(text: band.label, tint: band.tint)
                        .font(.subheadline.weight(.semibold))
                }
                Text(band.verdict(illnessFlagged: isIllnessFlagged))
                    .font(.title2.weight(.semibold))
                RecoveryZones(score: score, usual: usual)
                    .padding(.top, 12)
            } else {
                Text("WHOOP hasn't scored recovery for this day yet.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
