import SwiftUI

/// A coloured dot beside a word. The word carries the meaning; the colour
/// only reinforces it.
struct StatusLabel<Tint: ShapeStyle>: View {
    let text: String
    let tint: Tint

    @ScaledMetric(relativeTo: .body) private var dotSize = 8.0

    var body: some View {
        // Aligned to the first line, not centred: at large text sizes the word wraps,
        // and a centred dot floats between the lines instead of marking the first.
        // The dot's centre sits half its size above the baseline — about mid x-height,
        // and it scales with the text because `dotSize` does.
        HStack(alignment: .firstTextBaseline, spacing: dotSize * 0.75) {
            Circle()
                .fill(tint)
                .frame(width: dotSize, height: dotSize)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + dotSize * 0.5 }
            Text(text)
        }
        .accessibilityElement(children: .combine)
    }
}
