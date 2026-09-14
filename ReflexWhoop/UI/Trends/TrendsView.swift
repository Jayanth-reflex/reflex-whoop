import SwiftUI

/// Every metric's recent history at a glance, plus the ways into Patterns
/// and Unusual days.
struct TrendsView: View {
    @Environment(AppContainer.self) private var container

    @State private var range = HistoryRange.thirtyDays
    @State private var content: TrendsContent?
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            List {
                Group {
                    Section {
                        HistoryRangePicker(selection: $range)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())

                    if let loadError {
                        Section {
                            InlineMessage(text: loadError)
                        }
                    }

                    ForEach(Metric.Section.allCases, id: \.self) { section in
                        Section {
                            ForEach(section.metrics) { metric in
                                NavigationLink(value: metric) {
                                    TrendRow(metric: metric, points: content?.histories[metric] ?? [])
                                }
                            }
                        } header: {
                            SectionHeader(title: section.title)
                        }
                    }

                    if let content {
                        Section {
                            NavigationLink(value: TrendsLink.patterns) {
                                SubtitledRow(title: "What goes with your recovery", subtitle: content.patterns.headline)
                            }
                            NavigationLink(value: TrendsLink.unusualDays(range)) {
                                SubtitledRow(title: "Unusual days", subtitle: unusualDaysSubtitle(content.unusualDayCount))
                            }
                        } header: {
                            SectionHeader(title: "Patterns")
                        }
                    }
                }
                .listRowBackground(Color.surface)
            }
            .navigationTitle("Trends")
            .navigationSubtitle(range.title)
            .navigationDestination(for: Metric.self) { metric in
                MetricDetailView(metric: metric, initialRange: range)
            }
            .navigationDestination(for: TrendsLink.self) { link in
                switch link {
                case .patterns: PatternsView()
                case .unusualDays(let range): UnusualDaysView(range: range)
                }
            }
            .task(id: range) { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        do {
            content = try await container.database.dbPool.read { [range] db in
                try TrendsContent.load(db, range: range, now: .now)
            }
            loadError = nil
        } catch {
            loadError = "Couldn't load your trends: \(error.localizedDescription)"
        }
    }

    private func unusualDaysSubtitle(_ count: Int) -> String {
        count == 0 ? "None \(range.withinPhrase)" : "\(count) \(range.withinPhrase)"
    }
}
