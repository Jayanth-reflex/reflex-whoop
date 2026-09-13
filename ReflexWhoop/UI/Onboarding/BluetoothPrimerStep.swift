import SwiftUI

/// Explains the Bluetooth prompt before iPhone shows it, so the answer is an
/// informed one. "Not now" skips recording without ever triggering the prompt.
struct BluetoothPrimerStep: View {
    let allow: () -> Void
    let notNow: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Image(systemName: "applewatch")
                    .font(.system(size: 36))
                    .frame(width: 84, height: 84)
                    .background(Color.surface, in: .circle)
                    .padding(22)
                    .overlay {
                        Circle().strokeBorder(.quaternary, lineWidth: 1.5)
                    }
                    .accessibilityHidden(true)

                VStack(spacing: 10) {
                    Text("Let ReflexWhoop hear your band")
                        .font(.display(.title))
                    Text("iPhone will ask for Bluetooth access next. It's only used to read from your WHOOP band.")
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)

                Label("The app can't change any setting, alarm or clock on the band.", systemImage: "lock")
                    .font(.subheadline)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.surface, in: .rect(cornerRadius: 24))
            }
            .padding()
            .padding(.top, 24)
        }
        .safeAreaInset(edge: .bottom) {
            OnboardingActions(primaryTitle: "Continue", primary: allow, secondaryTitle: "Not now", secondary: notNow)
        }
    }
}
