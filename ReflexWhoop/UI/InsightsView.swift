import SwiftUI

/// Phase 3: ranked correlation cards (rho, n, strength), anomaly timeline, monthly recap.
struct InsightsView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView("No insights yet", systemImage: "sparkles")
                .navigationTitle("Insights")
        }
    }
}
