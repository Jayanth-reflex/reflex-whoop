import SwiftUI

/// Label leading, value trailing in the secondary style, stacking when the
/// text is too large to share a line.
///
/// Set once at the root: the app's ivory foreground style would otherwise
/// make every value primary, since the automatic style's grey is a default,
/// not an explicit style.
struct SecondaryValueLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                configuration.label
                Spacer(minLength: 0)
                configuration.content
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                configuration.label
                configuration.content
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

extension LabeledContentStyle where Self == SecondaryValueLabeledContentStyle {
    static var secondaryValue: SecondaryValueLabeledContentStyle { SecondaryValueLabeledContentStyle() }
}
