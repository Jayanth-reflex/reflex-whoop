import SwiftUI

/// WHOOP's 0–100 recovery scale split at its own band edges. Only the band
/// the score is in carries colour; a bracket above marks the person's usual
/// range.
struct RecoveryZones: View {
    let score: Double
    let usual: NormalRange?

    /// The marker's radius plus half its stroke, so it isn't clipped at 0 or 100.
    private static let inset = 11.5
    private static let markerRadius = 10.0
    private static let zoneHeight = 10.0
    private static let zoneGap = 4.0
    private static let bracketHeight = 6.0

    var body: some View {
        VStack(spacing: 6) {
            if let usual {
                ScaleLabelLayout(inset: Self.inset) {
                    Text(usualText(usual))
                        .scalePosition(unitScale.position((usual.lowerBound + usual.upperBound) / 2))
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }

            Canvas(renderer: draw)
                .frame(height: Self.bracketHeight + Self.markerRadius * 2 + 4)

            ScaleLabelLayout(inset: Self.inset) {
                ForEach(RecoveryBand.allCases, id: \.self) { band in
                    Text(band.label)
                        .scalePosition(unitScale.position((band.lowerBound + band.upperBound) / 2))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(usual.map(usualText) ?? "")
        .accessibilityHidden(usual == nil)
    }

    /// Proportions only; the canvas supplies the width.
    private var unitScale: HorizontalScale {
        HorizontalScale(domain: RecoveryBand.scale, inset: 0, width: 1)
    }

    private func usualText(_ usual: NormalRange) -> String {
        let lower = Metric.recovery.formatted(max(usual.lowerBound, RecoveryBand.scale.lowerBound))
        let upper = Metric.recovery.formatted(min(usual.upperBound, RecoveryBand.scale.upperBound))
        return "Your usual \(lower)–\(upper)"
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let scale = HorizontalScale(domain: RecoveryBand.scale, inset: Self.inset, width: size.width)
        let zoneMidY = Self.bracketHeight + Self.markerRadius + 2
        let current = RecoveryBand(score: score)

        if let usual {
            var bracket = Path()
            bracket.move(to: CGPoint(x: scale.x(usual.lowerBound), y: Self.bracketHeight))
            bracket.addLine(to: CGPoint(x: scale.x(usual.lowerBound), y: 0.75))
            bracket.addLine(to: CGPoint(x: scale.x(usual.upperBound), y: 0.75))
            bracket.addLine(to: CGPoint(x: scale.x(usual.upperBound), y: Self.bracketHeight))
            context.stroke(bracket, with: .style(.tertiary), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
        }

        for band in RecoveryBand.allCases {
            let startGap = band == RecoveryBand.allCases.first ? 0 : Self.zoneGap / 2
            let endGap = band == RecoveryBand.allCases.last ? 0 : Self.zoneGap / 2
            let start = scale.x(band.lowerBound) + startGap
            let zone = CGRect(
                x: start,
                y: zoneMidY - Self.zoneHeight / 2,
                width: scale.x(band.upperBound) - endGap - start,
                height: Self.zoneHeight
            )
            context.fill(Capsule().path(in: zone), with: band == current ? .color(band.tint) : .style(.quaternary))
        }

        let marker = Path(circleAround: CGPoint(x: scale.x(score), y: zoneMidY), radius: Self.markerRadius)
        context.fill(marker, with: .color(.onyx))
        context.stroke(marker, with: .style(.primary), lineWidth: 3)
    }
}
