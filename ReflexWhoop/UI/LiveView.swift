import SwiftUI

/// Phase 4: connect to the band over BLE, pick channels, stream live HR/RR/PPG/accel.
/// Deliberately built last — see docs/PROTOCOL-GEN5.md for why.
struct LiveView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "BLE not implemented yet",
                systemImage: "dot.radiowaves.left.and.right",
                description: Text("Direct band streaming lands in Phase 4, after the Gen 5 protocol discovery spike.")
            )
            .navigationTitle("Live")
        }
    }
}
