import SwiftUI

/// One of Welcome's promises: a symbol, a short title and a line of detail.
struct PromiseRow: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
                .font(.title2)
                .frame(width: 36)
        }
        .accessibilityElement(children: .combine)
    }
}
