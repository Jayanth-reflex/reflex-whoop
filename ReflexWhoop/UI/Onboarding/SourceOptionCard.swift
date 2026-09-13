import SwiftUI

/// A source that can be chosen or left out, as a card with a check.
struct SourceOptionCard: View {
    @Binding var isSelected: Bool
    let title: String
    let detail: String
    let note: String
    let systemImage: String

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(detail)
                        .foregroundStyle(.secondary)
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 5)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? AnyShapeStyle(Color.accent) : AnyShapeStyle(.tertiary))
            }
            .multilineTextAlignment(.leading)
            .padding()
            .background(Color.surface, in: .rect(cornerRadius: 26))
            .overlay {
                RoundedRectangle(cornerRadius: 26)
                    .strokeBorder(isSelected ? Color.accent : .clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .sensoryFeedback(.selection, trigger: isSelected)
    }

    private func toggle() {
        isSelected.toggle()
    }
}
