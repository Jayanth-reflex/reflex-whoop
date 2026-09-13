import SwiftUI

/// Uppercase, tracked list section header.
struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
    }
}
