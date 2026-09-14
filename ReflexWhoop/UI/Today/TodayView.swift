import GRDB
import SwiftUI

/// Today: WHOOP's scores for the latest day it scored, or the band's heart
/// rate when there are no scores to show.
struct TodayView: View {
    @Environment(AppContainer.self) private var container

    @State private var content: TodayContent?
    @State private var loadError: String?
    @State private var syncError: String?

    var body: some View {
        NavigationStack {
            Group {
                if let content {
                    TodayLayoutView(content: content, message: syncError ?? loadError)
                } else if let loadError {
                    ContentUnavailableView("Today couldn't load", systemImage: "exclamationmark.triangle", description: Text(loadError).foregroundStyle(.secondary))
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Today")
            .navigationSubtitle(subtitle)
            .navigationDestination(for: Metric.self) { metric in
                MetricDetailView(metric: metric)
            }
            .task { await observe() }
            .refreshable { await refresh() }
        }
    }

    private var subtitle: Text {
        if content?.layout == .scores, let date = content?.snapshot?.date {
            Text(date, format: .dateTime.weekday(.wide).day().month(.wide))
        } else {
            Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
        }
    }

    /// Follows the database for as long as Today is on screen, so a sync that
    /// finishes later (the first one, a background one) shows up by itself.
    private func observe() async {
        let readings = TodayReadings.observation(since: Calendar.current.startOfDay(for: .now))
        do {
            for try await reading in readings.values(in: container.database.dbPool) {
                content = TodayContent(snapshot: reading.snapshot, sources: await container.sourceSnapshot(), heartRateToday: reading.heartRateToday)
                loadError = nil
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Pull to refresh brings in new WHOOP data, when an account is connected.
    /// What arrives reaches the screen through `observe()`.
    private func refresh() async {
        guard let engine = await container.syncEngine() else {
            syncError = nil
            return
        }
        do {
            _ = try await engine.syncNow(trigger: "pull")
            syncError = nil
        } catch {
            syncError = "Couldn't sync with WHOOP: \(error.localizedDescription)"
        }
    }
}
