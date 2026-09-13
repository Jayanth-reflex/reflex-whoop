import SwiftUI

/// Everything held on this iPhone, where it comes from, and the ways to take
/// a copy or rebuild the band's readings.
struct ArchiveView: View {
    @Binding var selection: AppTab

    @Environment(AppContainer.self) private var container

    @State private var sources: AppContainer.SourceSnapshot?
    @State private var byteCount: Int64 = 0
    @State private var isShowingExport = false
    @State private var isConfirmingRebuild = false
    @State private var isRebuilding = false
    @State private var rebuildOutcome: String?

    var body: some View {
        NavigationStack {
            List {
                if let sources {
                    Group {
                        Section {
                            ArchiveSummaryHeader(archive: sources.archive, byteCount: byteCount)
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())

                        Section {
                            NavigationLink(value: ArchiveLink.whoopAccount) {
                                SourceRow(title: "WHOOP account", systemImage: "icloud", status: whoopStatus(sources.whoop), tint: sources.whoop.tint)
                            }
                            // Switches tab rather than pushing, so no disclosure indicator.
                            Button(action: showBand) {
                                SourceRow(title: "Band", systemImage: "applewatch", status: bandStatus(sources.band), tint: bandTint)
                            }
                            .tint(Color.ivory)
                            .accessibilityHint("Opens the Band tab")
                        } header: {
                            SectionHeader(title: "Sources")
                        }

                        Section {
                            Button("Export a copy", systemImage: "square.and.arrow.up", action: showExport)
                            Button("Rebuild heart-rate history", systemImage: "arrow.clockwise", action: askToRebuild)
                                .disabled(isRebuilding || sources.archive.bleSessionCount == 0)
                                .confirmationDialog("Rebuild heart-rate history?", isPresented: $isConfirmingRebuild, titleVisibility: .visible) {
                                    Button("Rebuild", action: startRebuild)
                                } message: {
                                    Text("Reads all \(sources.archive.bleSessionCount) band recordings again to recreate the readings. The recordings themselves aren't changed.")
                                }
                            if isRebuilding {
                                LabeledContent("Rebuilding…") {
                                    ProgressView()
                                }
                            } else if let rebuildOutcome {
                                Text(rebuildOutcome)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        } header: {
                            SectionHeader(title: "Your data")
                        } footer: {
                            SectionFooter(text: "The app never deletes anything. Deleting the app does, so keep an exported copy somewhere safe.")
                        }

                        Section {
                            ForEach(AboutTopic.allCases, id: \.self) { topic in
                                NavigationLink(topic.title, value: ArchiveLink.about(topic))
                            }
                        } header: {
                            SectionHeader(title: "About")
                        }
                    }
                    .listRowBackground(Color.surface)
                }
            }
            .navigationTitle("Archive")
            .navigationSubtitle("On this iPhone")
            .navigationDestination(for: ArchiveLink.self) { link in
                switch link {
                case .whoopAccount: WhoopAccountView()
                case .about(let topic): AboutView(topic: topic)
                }
            }
            .sheet(isPresented: $isShowingExport) {
                ExportSheet(databaseByteCount: byteCount)
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private var bandTint: AnyShapeStyle {
        container.continuousRecorder == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.jade)
    }

    private func whoopStatus(_ state: SourceState) -> String {
        guard case .active(let lastSuccess?) = state else { return state.statusText }
        return "\(state.statusText) · synced \(lastSuccess.formatted(.relative(presentation: .named)))"
    }

    private func bandStatus(_ state: SourceState) -> String {
        if container.continuousRecorder != nil { return "Recording" }
        guard case .active(let lastRecording?) = state else { return "Not set up" }
        return "Last recorded \(lastRecording.formatted(.relative(presentation: .named)))"
    }

    private func load() async {
        sources = await container.sourceSnapshot()
        byteCount = container.database.onDiskByteCount()
    }

    private func showBand() {
        selection = .band
    }

    private func showExport() {
        isShowingExport = true
    }

    private func askToRebuild() {
        isConfirmingRebuild = true
    }

    private func startRebuild() {
        Task { await rebuild() }
    }

    private func rebuild() async {
        isRebuilding = true
        defer { isRebuilding = false }
        do {
            let stats = try await container.replayBleNormalization()
            rebuildOutcome = "Rebuilt \(stats.samplesWritten.formatted()) readings from \(stats.sessionsProcessed.formatted()) recordings."
        } catch {
            rebuildOutcome = "Couldn't rebuild: \(error.localizedDescription)"
        }
        await load()
    }
}
