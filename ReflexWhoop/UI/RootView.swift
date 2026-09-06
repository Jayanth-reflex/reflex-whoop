import SwiftUI

struct RootView: View {
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
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(.green)
    }
}

#Preview {
    RootView()
}
