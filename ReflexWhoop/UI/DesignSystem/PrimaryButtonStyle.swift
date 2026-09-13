import SwiftUI

/// The one filled action on a screen: a champagne capsule. Feedback lands on
/// touch-down, and a disabled button drops to a quiet surface.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(isEnabled ? AnyShapeStyle(Color.onChampagne) : AnyShapeStyle(.tertiary))
            .padding(.horizontal)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(isEnabled ? Color.accent : Color.surfaceRaised, in: .capsule)
            .contentShape(.capsule)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}
