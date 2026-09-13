import SwiftUI

/// Choose WHOOP, the band, or both.
struct SourcesStep: View {
    @Binding var wantsWhoop: Bool
    @Binding var wantsBand: Bool
    let next: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Where should data come from?")
                        .font(.display(.title))
                    Text("Use either or both. You can change this later in Archive.")
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 14) {
                    SourceOptionCard(
                        isSelected: $wantsWhoop,
                        title: "WHOOP account",
                        detail: "Recovery, sleep, strain and HRV, including your past history.",
                        note: "Needs an active membership and a free WHOOP developer app.",
                        systemImage: "icloud"
                    )
                    SourceOptionCard(
                        isSelected: $wantsBand,
                        title: "Band over Bluetooth",
                        detail: "Live heart rate straight from the band.",
                        note: "Needs no account and no internet.",
                        systemImage: "applewatch"
                    )
                }
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) {
            OnboardingActions(primaryTitle: "Continue", primary: next, isPrimaryEnabled: wantsWhoop || wantsBand)
        }
    }
}
