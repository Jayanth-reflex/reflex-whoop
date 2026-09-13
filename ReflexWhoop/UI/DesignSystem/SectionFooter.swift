import SwiftUI

/// List section footer text. Sets the secondary style explicitly: the app's
/// ivory foreground style would otherwise replace the footer's default grey.
struct SectionFooter: View {
    let text: String

    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
    }
}
