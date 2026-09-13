import SwiftUI

/// A coloured dot beside a word. The word carries the meaning; the colour
/// only reinforces it.
struct StatusLabel<Tint: ShapeStyle>: View {
    let text: String
    let tint: Tint

    @ScaledMetric(relativeTo: .body) private var dotSize = 8.0

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Circle()
                .fill(tint)
                .frame(width: dotSize, height: dotSize)
        }
    }
}
