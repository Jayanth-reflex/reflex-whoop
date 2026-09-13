import SwiftUI

/// What moved with next-morning recovery. Weak results are shown without a
/// direction, since at that size "helps" and "hurts" are equally likely noise.
struct PatternsView: View {
    @Environment(AppContainer.self) private var container

    @State private var summary: PatternsSummary?
    @State private var loadError: String?

    var body: some View {
        List {
            Group {
                if let loadError {
                    Section {
                        InlineMessage(text: loadError)
                    }
                }
                if let summary {
                    if summary.comparedCount == 0, summary.building.isEmpty {
                        Section {
                            ContentUnavailableView(
                                "No patterns yet",
                                systemImage: "chart.dots.scatter",
                                description: Text("This needs about a month of days before it can tell a pattern from noise.").foregroundStyle(.secondary)
                            )
                        }
                    } else {
                        Section {
                            PatternsHeadline(summary: summary)
                        }
                        .listRowBackground(Color.clear)

                        PatternsSections(summary: summary)
                    }
                }
            }
            .listRowBackground(Color.surface)
        }
        .navigationTitle("Patterns")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        do {
            let rows = try await container.database.dbPool.read(AnalysisQueries.correlations)
            summary = PatternsSummary(rows: rows)
            loadError = nil
        } catch {
            loadError = "Couldn't load patterns: \(error.localizedDescription)"
        }
    }
}
