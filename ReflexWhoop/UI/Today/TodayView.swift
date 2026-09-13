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
            .task { await load() }
            .refreshable { await refresh() }
        }
    }

    private var subtitle: Text {
        if content?.layout == .scores, let day = content?.snapshot?.metrics.day, let date = RecordDAO.date(forDay: day) {
            Text(date, format: .dateTime.weekday(.wide).day().month(.wide).recordedDay())
        } else {
            Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
        }
    }

    private func load() async {
        let sources = await container.sourceSnapshot()
        let startOfToday = Calendar.current.startOfDay(for: .now)
        do {
            let (snapshot, heartRate) = try await container.database.dbPool.read { db in
                (try TodaySnapshot.load(db), try RecordingQueries.heartRate(db, since: startOfToday))
            }
            content = TodayContent(snapshot: snapshot, sources: sources, heartRateToday: heartRate)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Pull to refresh brings in new WHOOP data first, when an account is connected.
    private func refresh() async {
        if let engine = await container.syncEngine() {
            do {
                _ = try await engine.syncNow(trigger: "pull")
                syncError = nil
            } catch {
                syncError = "Couldn't sync with WHOOP: \(error.localizedDescription)"
            }
        }
        await load()
    }
}
