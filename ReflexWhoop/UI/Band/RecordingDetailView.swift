import SwiftUI

/// One recording: when it ran, its heart rate across that time in one-minute
/// averages, and what else was kept from it.
struct RecordingDetailView: View {
    let recording: RecordingSummary

    @Environment(AppContainer.self) private var container

    @State private var readings: [HeartRateReading] = []
    @State private var loadError: String?

    var body: some View {
        List {
            Group {
                Section {
                    RecordingHeader(recording: recording)
                }
                .listRowBackground(Color.clear)

                if let average = recording.averageBpm, let lowest = recording.lowestBpm, let highest = recording.highestBpm {
                    Section {
                        HStack(alignment: .top) {
                            StatValue(title: "Average", value: average.formatted(.number.precision(.fractionLength(0))), unit: "bpm")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            StatValue(title: "Lowest", value: lowest.formatted(), unit: "bpm")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            StatValue(title: "Highest", value: highest.formatted(), unit: "bpm")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                if let loadError {
                    Section {
                        InlineMessage(text: loadError)
                    }
                } else if readings.count > 1 {
                    Section {
                        HeartRateChart(readings: readings, maximumGap: 3 * 60)
                            .frame(height: 190)
                            .padding(.vertical, 8)
                    } footer: {
                        SectionFooter(text: "One-minute averages. Breaks are minutes with no readings.")
                    }
                }

                Section {
                    Label {
                        SubtitledRow(title: "Heart rate", subtitle: recording.readingCount > 0 ? "Readable · \(recording.readingCount.formatted()) readings" : "Nothing readable")
                    } icon: {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.jade)
                    }
                    Label {
                        SubtitledRow(title: "Everything else the band sent", subtitle: "Saved as received · not readable yet")
                    } icon: {
                        Image(systemName: "clock")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    SectionHeader(title: "What was captured")
                } footer: {
                    SectionFooter(text: "Recordings are kept exactly as the band sent them, so they can be read again as more signals are understood. The app never deletes them.")
                }
            }
            .listRowBackground(Color.surface)
        }
        .listSectionSpacing(.compact)
        .navigationTitle("Recording")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        do {
            readings = try await container.database.dbPool.read { [id = recording.id] db in
                try RecordingQueries.minuteReadings(db, sessionID: id)
            }
            loadError = nil
        } catch {
            loadError = "Couldn't load this recording: \(error.localizedDescription)"
        }
    }
}
