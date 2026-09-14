import SwiftUI

struct RootView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale

    @State private var selection = AppTab.today
    @State private var isShowingOnboarding = false
    @AppStorage(Onboarding.completedKey) private var hasCompletedOnboarding = false
    @AppStorage(TemperaturePreference.key) private var temperaturePreference = TemperaturePreference.system

    var body: some View {
        TabView(selection: $selection) {
            Tab("Today", systemImage: "sun.max", value: AppTab.today) {
                TodayView()
            }
            Tab("Trends", systemImage: "chart.line.uptrend.xyaxis", value: AppTab.trends) {
                TrendsView()
            }
            Tab("Band", systemImage: "applewatch", value: AppTab.band) {
                BandView()
            }
            Tab("Archive", systemImage: "archivebox", value: AppTab.archive) {
                ArchiveView(selection: $selection)
            }
        }
        .tint(Color.accent)
        .environment(\.temperatureUnit, temperaturePreference.unit(locale: locale))
        .fullScreenCover(isPresented: $isShowingOnboarding) {
            OnboardingFlow(onFinish: finishOnboarding)
        }
        // Covers both a cold launch and a background→foreground transition —
        // the design doc's third sync trigger alongside manual and
        // BGAppRefreshTask. Debounced internally, so this is safe to fire on
        // every activation without hammering the API.
        .task {
            await decideOnboarding()
            await container.normalizeBleIfNeeded()
            await container.syncIfDueOnForeground()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await container.syncIfDueOnForeground() }
            }
        }
    }

    private func decideOnboarding() async {
        guard !hasCompletedOnboarding else { return }
        let sources = await container.sourceSnapshot()
        if Onboarding.shouldPresent(hasCompleted: hasCompletedOnboarding, archiveIsEmpty: sources.archive.isEmpty, hasWhoopAccount: sources.whoop != .notConfigured) {
            isShowingOnboarding = true
        } else {
            hasCompletedOnboarding = true
        }
    }

    private func finishOnboarding() {
        hasCompletedOnboarding = true
        isShowingOnboarding = false
    }
}
