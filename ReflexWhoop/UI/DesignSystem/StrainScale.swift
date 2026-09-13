import SwiftUI

/// Day strain on WHOOP's 0–21 scale. The scale is logarithmic, so it's labelled
/// as a scale rather than filled like a percentage bar.
///
/// Hidden from VoiceOver: the row showing it states the strain and its band.
struct StrainScale: View {
    let strain: Double

    private static let trackHeight = 8.0
    private static let markerRadius = 8.0
    private static let markerStroke = 3.0
    private static let inset = markerRadius + markerStroke / 2
    private static let domain = 0...StrainBand.scaleMaximum

    var body: some View {
        VStack(spacing: 6) {
            Canvas(renderer: draw)
                .frame(height: Self.inset * 2)

            ScaleLabelLayout(inset: Self.inset) {
                ForEach(Array(stride(from: 0, through: StrainBand.scaleMaximum, by: 7)), id: \.self) { tick in
                    Text(tick, format: .number)
                        .scalePosition(tick / StrainBand.scaleMaximum)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            // Labels share one line along the scale; beyond this they collide.
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        }
        .accessibilityHidden(true)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let scale = HorizontalScale(domain: Self.domain, inset: Self.inset, width: size.width)
        let midY = size.height / 2
        let track = CGRect(x: 0, y: midY - Self.trackHeight / 2, width: size.width, height: Self.trackHeight)
        let markerX = scale.x(strain)
        context.fill(Capsule().path(in: track), with: .style(.quinary))
        context.fill(Capsule().path(in: CGRect(x: 0, y: track.minY, width: markerX, height: Self.trackHeight)), with: .color(.accent))

        let marker = Path(circleAround: CGPoint(x: markerX, y: midY), radius: Self.markerRadius)
        context.fill(marker, with: .color(.onyx))
        context.stroke(marker, with: .color(.accent), lineWidth: Self.markerStroke)
    }
}
