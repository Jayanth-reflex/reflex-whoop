import SwiftUI

struct RootView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "circle.dashed.inset.filled") }
            TrendsView()
                .tabItem { Label("Trends", systemImage: "chart.xyaxis.line") }
            InsightsView()
                .tabItem { Label("Insights", systemImage: "sparkles") }
            LiveView()
                .tabItem { Label("Live", systemImage: "waveform.path.ecg") }
            DataView()
                .tabItem { Label("Data", systemImage: "cylinder.split.1x2") }
        }
        .tint(.green)
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

#Preview {
    RootView()
}
