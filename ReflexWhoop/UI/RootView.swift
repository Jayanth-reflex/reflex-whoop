import SwiftUI

struct RootView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.scenePhase) private var scenePhase

    @State private var selection = AppTab.today

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
        // Covers both a cold launch and a background→foreground transition —
        // the design doc's third sync trigger alongside manual and
        // BGAppRefreshTask. Debounced internally, so this is safe to fire on
        // every activation without hammering the API.
        .task {
            await container.normalizeBleIfNeeded()
            await container.syncIfDueOnForeground()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await container.syncIfDueOnForeground() }
            }
        }
    }
}
