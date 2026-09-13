import SwiftUI

/// A few statistics in equal columns, or one under another when the columns
/// can't fit at the current text size.
struct StatRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                Group(subviews: content) { subviews in
                    ForEach(subviews) { subview in
                        subview.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                content
            }
        }
    }
}
