import SwiftUI

/// Live heart rate from the band, the Keep recording switch, and past
/// recordings. Recording is one setting: on, the app holds the connection and
/// reconnects by itself; off, it lets go of the band.
struct BandView: View {
    @Environment(AppContainer.self) private var container

    /// Observed rather than copied, so turning recording on elsewhere (first
    /// run) shows here too.
    @AppStorage(CollectionSettings.continuousKey) private var keepRecording = false
    @State private var recordings: [RecordingSummary] = []
    @State private var loadError: String?

    private var recorder: SpikeRecorder? { container.continuousRecorder }
    private var presentation: BandPresentation { BandPresentation(connection: recorder?.connectionState) }

    /// The session in progress isn't summarised until it ends, so it's left
    /// out of the list rather than shown as empty.
    private var pastRecordings: [RecordingSummary] {
        recordings.filter { $0.id != recorder?.sessionID }
    }

    var body: some View {
        NavigationStack {
            List {
                Group {
                    Section {
                        if presentation == .live, let recorder {
                            LiveHeartRateSection(recorder: recorder)
                        } else {
                            BandStateView(presentation: presentation, startRecording: startRecording)
                        }
                    }
                    .listRowBackground(Color.clear)

                    if keepRecording {
                        RecordingSettingsSection(keepRecording: $keepRecording, recorder: recorder)
                    }

                    if let message = container.recordingStartError.map({ "Couldn't start recording: \($0)" }) ?? loadError {
                        Section {
                            InlineMessage(text: message)
                        }
                    }

                    if !pastRecordings.isEmpty {
                        Section {
                            ForEach(pastRecordings.prefix(3)) { recording in
                                NavigationLink(value: recording) {
                                    RecordingRow(recording: recording)
                                }
                            }
                            NavigationLink(value: BandLink.allRecordings) {
                                LabeledContent("All recordings", value: pastRecordings.count.formatted())
                            }
                        } header: {
                            SectionHeader(title: "Recent")
                        }
                    }

                    if recorder != nil {
                        Section {
                            NavigationLink("Signal details", value: BandLink.signalDetails)
                        }
                    }

                    Section {
                    } footer: {
                        Label("Only reads from your band. It can't change anything on it.", systemImage: "lock")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .listRowBackground(Color.surface)
            }
            .navigationTitle("Band")
            .navigationSubtitle(subtitle)
            .navigationDestination(for: RecordingSummary.self) { recording in
                RecordingDetailView(recording: recording)
            }
            .navigationDestination(for: BandLink.self) { link in
                switch link {
                case .allRecordings:
                    RecordingsListView(recordings: pastRecordings)
                case .signalDetails:
                    if let recorder {
                        SignalDetailsView(recorder: recorder)
                    }
                }
            }
            .onChange(of: keepRecording) {
                container.setContinuousCollection(keepRecording)
            }
            .task(id: recorder?.sessionID) { await loadRecordings() }
            .refreshable { await loadRecordings() }
        }
    }

    private var subtitle: String {
        switch presentation {
        case .idle: "Not recording"
        case .live: "Connected · recording"
        case .searching: "Looking for your band"
        case .bluetoothOff: "Bluetooth is off"
        case .bluetoothDenied: "Bluetooth not allowed"
        case .unsupported: "Bluetooth unavailable"
        }
    }

    /// Also retries when recording is already switched on but couldn't start.
    private func startRecording() {
        if keepRecording {
            container.setContinuousCollection(true)
        } else {
            keepRecording = true
        }
    }

    private func loadRecordings() async {
        do {
            recordings = try await container.database.dbPool.read { db in
                try RecordingQueries.recent(db, limit: nil)
            }
            loadError = nil
        } catch {
            loadError = "Couldn't load recordings: \(error.localizedDescription)"
        }
    }
}
