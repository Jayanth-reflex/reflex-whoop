import SwiftUI

/// Placeholder for Phase 1. Phase 3 fills this in per the design doc: a one-sentence
/// verdict at top, recovery ring, strain-so-far, last night's sleep, readiness,
/// active anomalies, and the band/sync status strip.
struct TodayView: View {
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Not connected yet",
                systemImage: "bolt.horizontal.circle",
                description: Text("Connect your WHOOP account in Settings to start collecting data.")
            )
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    // Settings lives behind a toolbar action, not a 6th tab —
                    // iOS collapses anything past 5 tabs into an auto-generated
                    // "More" list, which is worse UX than a standard gear icon.
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        }
    }
}
