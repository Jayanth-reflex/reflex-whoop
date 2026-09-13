import SwiftUI

/// A quiet in-place message for something that went wrong, shown where it
/// happened instead of in an alert.
struct InlineMessage: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}
