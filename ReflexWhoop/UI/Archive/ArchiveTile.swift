import SwiftUI

/// A figure with its caption beneath, on a card.
struct ArchiveTile: View {
    let value: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            // Each tile gets an equal third of the row, which is narrower than a value
            // like "251.8 MB" at this size; shrinking a little beats breaking "MB" onto
            // its own line. When the row can't fit at all, `StatRow` stacks the tiles.
            Text(value)
                .font(.title3)
                .bold()
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
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
