import SwiftUI

/// Two pieces of content side by side when they fit on one line at their
/// natural size, stacked when they don't, so large Dynamic Type sizes wrap
/// whole pieces instead of squeezing each into fragments.
struct AdaptiveRow<Leading: View, Trailing: View>: View {
    var alignment = VerticalAlignment.center
    var spacing = 12.0
    /// Push the trailing content to the far edge when side by side.
    var pinsTrailing = true
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: alignment, spacing: spacing) {
                leading
                if pinsTrailing {
                    Spacer(minLength: 0)
                }
                trailing
            }
            VStack(alignment: .leading, spacing: 4) {
                leading
                trailing
            }
            .environment(\.isAdaptiveRowStacked, true)
            // A list row otherwise sizes the stack before its text wraps,
            // truncating the last line.
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension EnvironmentValues {
    /// True inside an `AdaptiveRow` that has stacked its content.
    @Entry var isAdaptiveRowStacked = false
}
