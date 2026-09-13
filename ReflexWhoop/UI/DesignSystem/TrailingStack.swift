import SwiftUI

/// A vertical stack for the trailing side of an `AdaptiveRow`: aligned to the
/// trailing edge beside the leading content, to the leading edge once stacked
/// beneath it.
struct TrailingStack<Content: View>: View {
    var spacing = 6.0
    @ViewBuilder let content: Content

    @Environment(\.isAdaptiveRowStacked) private var isStacked

    var body: some View {
        VStack(alignment: isStacked ? .leading : .trailing, spacing: spacing) {
            content
        }
    }
}
