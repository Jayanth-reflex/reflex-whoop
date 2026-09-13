import SwiftUI

/// A figure with its caption beneath, on a card.
struct ArchiveTile: View {
    let value: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.title3)
                .bold()
                .monospacedDigit()
            Text(caption)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.surface, in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}
