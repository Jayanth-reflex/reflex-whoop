import SwiftUI

/// One metric's latest value and history, against the person's normal.
/// Shared by Today and Trends.
struct MetricDetailView: View {
    let metric: Metric

    @Environment(AppContainer.self) private var container

    @State private var range: HistoryRange
    @State private var points: [MetricPoint] = []
    @State private var hasLoaded = false
    @State private var loadError: String?

    /// Opens on `initialRange`, so a metric picked on Trends keeps its span.
    init(metric: Metric, initialRange: HistoryRange = .thirtyDays) {
        self.metric = metric
        _range = State(initialValue: initialRange)
    }

    var body: some View {
        List {
            Group {
                if let latest = points.last {
                    Section {
                        MetricDetailHeader(metric: metric, point: latest)
                    }
                    .listRowBackground(Color.clear)
                }

                Section {
                    Picker("Range", selection: $range) {
                        ForEach(HistoryRange.allCases) { range in
                            Text(range.label).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                if let loadError {
                    Section {
                        InlineMessage(text: loadError)
                    }
                } else if points.isEmpty, hasLoaded {
                    Section {
                        ContentUnavailableView("No readings in this range", systemImage: "chart.line.uptrend.xyaxis")
                    }
                } else if let summary = MetricHistorySummary(values: points.map(\.value)) {
                    Section {
                        MetricHistoryCard(metric: metric, points: points, summary: summary)
                    }
                    UnusualPointsSection(metric: metric, points: points.filter(\.status.isUnusual))
                }

                Section {
                    Text(metric.explanation)
                    LabeledContent("Source", value: metric.source)
                } header: {
                    SectionHeader(title: "About \(metric.shortLabel)")
                }
            }
            .listRowBackground(Color.surface)
        }
        .listSectionSpacing(.compact)
        .navigationTitle(metric.shortLabel)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: range) { await load() }
    }

    private func load() async {
        let firstDay = range.firstDay(endingOn: .now)
        do {
            points = try await container.database.dbPool.read { [metric] db in
                try MetricHistory.points(db, metric: metric, sinceDay: firstDay)
            }
            loadError = nil
        } catch {
            loadError = "Couldn't load this history: \(error.localizedDescription)"
        }
        hasLoaded = true
    }
}
