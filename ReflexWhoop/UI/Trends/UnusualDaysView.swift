import SwiftUI

/// Days `AnomalyEngine` flagged in a range, newest first, each with the
/// readings that were unusual and the normal they were judged against.
struct UnusualDaysView: View {
    let range: HistoryRange

    @Environment(AppContainer.self) private var container

    @State private var days: [UnusualDay] = []
    @State private var hasLoaded = false
    @State private var loadError: String?

    var body: some View {
        List {
            Group {
                Section {
                    Text("Days when a reading was more than twice as far from your normal as it usually strays.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Color.clear)

                if let loadError {
                    Section {
                        InlineMessage(text: loadError)
                    }
                } else if days.isEmpty, hasLoaded {
                    Section {
                        ContentUnavailableView(
                            "No unusual days",
                            systemImage: "checkmark.circle",
                            description: Text("Nothing was that far from your normal \(range.withinPhrase).").foregroundStyle(.secondary)
                        )
                    }
                }

                ForEach(days) { day in
                    UnusualDaySection(day: day)
                }
            }
            .listRowBackground(Color.surface)
        }
        .navigationTitle("Unusual days")
        .navigationSubtitle(range.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        let firstDay = range.firstDay(endingOn: .now)
        do {
            days = try await container.database.dbPool.read { db in
                try UnusualDays.load(db, sinceDay: firstDay)
            }
            loadError = nil
        } catch {
            loadError = "Couldn't load unusual days: \(error.localizedDescription)"
        }
        hasLoaded = true
    }
}
