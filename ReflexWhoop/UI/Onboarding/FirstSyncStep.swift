import SwiftUI

/// The first sync after connecting WHOOP. The app is usable straight away, so
/// Go to Today is always available; the sync carries on either way.
struct FirstSyncStep: View {
    let finish: () -> Void

    @Environment(AppContainer.self) private var container

    @State private var isSyncing = true
    @State private var history: WhoopHistory?
    @State private var errorText: String?

    var body: some View {
        List {
            Group {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(isSyncing ? "Bringing in your history" : "Your history is here")
                            .font(.display(.title))
                        Text(isSyncing ? "You can start using the app. This carries on in the background." : "Everything WHOOP had is now on this iPhone.")
                            .foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(Color.clear)

                Section {
                    FirstSyncRow(title: "Recovery and HRV", count: history?.recoveryDays, noun: "days", isSyncing: isSyncing)
                    FirstSyncRow(title: "Sleep", count: history?.sleepNights, noun: "nights", isSyncing: isSyncing)
                    FirstSyncRow(title: "Strain and workouts", count: history?.strainDays, noun: "days", isSyncing: isSyncing)
                } footer: {
                    if isSyncing {
                        SectionFooter(text: "Counts appear once WHOOP's records are in. A long history can take a few minutes.")
                    }
                }

                if let errorText {
                    Section {
                        InlineMessage(text: errorText)
                    }
                }
            }
            .listRowBackground(Color.surface)
        }
        .navigationBarBackButtonHidden()
        .safeAreaInset(edge: .bottom) {
            OnboardingActions(primaryTitle: "Go to Today", primary: finish)
        }
        .task { await sync() }
    }

    private func sync() async {
        defer { isSyncing = false }
        guard let engine = await container.syncEngine() else { return }
        // Unstructured on purpose: leaving this screen cancels its `.task`,
        // and the sync has to carry on after Go to Today.
        let work = Task { try await engine.syncNow(trigger: "onboarding") }
        do {
            _ = try await work.value
            errorText = nil
        } catch {
            errorText = "The sync stopped: \(error.localizedDescription). It'll try again next time you open the app."
        }
        history = try? await container.database.dbPool.read(WhoopHistory.load)
    }
}
