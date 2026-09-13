import SwiftUI

/// The buttons pinned to the bottom of a first-run screen.
struct OnboardingActions: View {
    let primaryTitle: String
    let primary: () -> Void
    var isPrimaryEnabled = true
    var secondaryTitle: String?
    var secondary: (() -> Void)?

    var body: some View {
        VStack(spacing: 6) {
            Button(primaryTitle, action: primary)
                .buttonStyle(.primary)
                .disabled(!isPrimaryEnabled)
            if let secondaryTitle, let secondary {
                Button(action: secondary) {
                    Text(secondaryTitle)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(.rect)
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}
