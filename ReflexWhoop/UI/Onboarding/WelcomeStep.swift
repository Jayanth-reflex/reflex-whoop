import SwiftUI

/// What ReflexWhoop is, in three promises.
struct WelcomeStep: View {
    let getStarted: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var iconSize = 112.0

    var body: some View {
        ScrollView {
            VStack(spacing: 44) {
                VStack(spacing: 8) {
                    Image(.appIconPreview)
                        .resizable()
                        .frame(width: iconSize, height: iconSize)
                        .clipShape(.rect(cornerRadius: iconSize * 0.2237))
                        .shadow(color: .black.opacity(0.4), radius: 12, y: 8)
                        .accessibilityHidden(true)
                    Text("ReflexWhoop")
                        .font(.display(.largeTitle))
                        .padding(.top, 16)
                    Text("Your WHOOP data, kept on your iPhone.")
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 24) {
                    PromiseRow(
                        title: "Yours to keep",
                        detail: "Everything is stored on this iPhone and can be exported whenever you like.",
                        systemImage: "archivebox"
                    )
                    PromiseRow(
                        title: "Works without a membership",
                        detail: "Heart rate comes straight from the band over Bluetooth.",
                        systemImage: "applewatch"
                    )
                    PromiseRow(
                        title: "Honest numbers",
                        detail: "Every reading is shown against your own normal. Missing data stays missing.",
                        systemImage: "chart.dots.scatter"
                    )
                }
                .padding(.horizontal, 8)
            }
            .padding(.horizontal, 32)
            .padding(.top, 40)
        }
        .safeAreaInset(edge: .bottom) {
            OnboardingActions(primaryTitle: "Get started", primary: getStarted)
        }
    }
}
