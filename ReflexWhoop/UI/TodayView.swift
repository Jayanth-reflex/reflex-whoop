import SwiftUI

/// Placeholder for Phase 1. Phase 3 fills this in per the design doc: a one-sentence
/// verdict at top, recovery ring, strain-so-far, last night's sleep, readiness,
/// active anomalies, and the band/sync status strip.
struct TodayView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Not connected yet",
                systemImage: "bolt.horizontal.circle",
                description: Text("Connect your WHOOP account in Settings to start collecting data.")
            )
            .navigationTitle("Today")
        }
    }
}
