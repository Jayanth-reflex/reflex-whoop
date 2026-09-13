import SwiftUI

/// First run: Welcome, choose sources, then set up each chosen source. Every
/// source can be skipped, and the flow ends on Today either way.
struct OnboardingFlow: View {
    let onFinish: () -> Void

    @Environment(AppContainer.self) private var container

    @State private var path: [OnboardingStep] = []
    @State private var wantsWhoop = true
    @State private var wantsBand = true

    var body: some View {
        NavigationStack(path: $path) {
            WelcomeStep(getStarted: showSources)
                .navigationDestination(for: OnboardingStep.self) { step in
                    switch step {
                    case .sources:
                        SourcesStep(wantsWhoop: $wantsWhoop, wantsBand: $wantsBand, next: afterSources)
                    case .bluetooth:
                        BluetoothPrimerStep(allow: allowBluetooth, notNow: afterBluetooth)
                    case .whoop:
                        WhoopCredentialsForm(onConnected: showFirstSync)
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Skip", action: onFinish)
                                }
                            }
                    case .firstSync:
                        FirstSyncStep(finish: onFinish)
                    }
                }
        }
    }

    private func showSources() {
        path.append(.sources)
    }

    private func afterSources() {
        if wantsBand {
            path.append(.bluetooth)
        } else {
            afterBluetooth()
        }
    }

    /// Turning recording on is what makes iPhone ask for Bluetooth access.
    private func allowBluetooth() {
        container.setContinuousCollection(true)
        afterBluetooth()
    }

    private func afterBluetooth() {
        if wantsWhoop {
            path.append(.whoop)
        } else {
            onFinish()
        }
    }

    private func showFirstSync() {
        path.append(.firstSync)
    }
}
