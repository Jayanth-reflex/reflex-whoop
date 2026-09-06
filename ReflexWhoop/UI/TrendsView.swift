import SwiftUI

/// Phase 3: metric x range picker, line chart with personal baseline band,
/// weekday breakdown, distribution histogram.
struct TrendsView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView("No data yet", systemImage: "chart.xyaxis.line")
                .navigationTitle("Trends")
        }
    }
}
