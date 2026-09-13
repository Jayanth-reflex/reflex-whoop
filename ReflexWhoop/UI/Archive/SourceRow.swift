import SwiftUI

/// A data source with its current state.
struct SourceRow: View {
    let title: String
    let systemImage: String
    let status: String
    let tint: AnyShapeStyle

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                StatusLabel(text: status, tint: tint)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
        }
        .accessibilityElement(children: .combine)
    }
}
