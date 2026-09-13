import SwiftUI

/// Takes a full copy of the archive into Files: readable CSVs, the raw
/// payloads exactly as received, and the database itself.
struct ExportSheet: View {
    /// The database's size, which the copy is at least as large as.
    let databaseByteCount: Int64

    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss

    @State private var isExporting = false
    @State private var result: Exporter.Result?
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            List {
                if let result {
                    ExportDoneSection(result: result)
                } else {
                    Section {
                        ExportContentRow(title: "Daily scores", systemImage: "doc.text", format: "CSV")
                        ExportContentRow(title: "WHOOP records", systemImage: "moon", format: "CSV")
                        ExportContentRow(title: "Band recordings", systemImage: "waveform.path.ecg", format: "CSV + raw")
                        ExportContentRow(title: "Everything, as one database", systemImage: "cylinder.split.1x2", format: "SQLite")
                    } header: {
                        Text("Files you can open on a computer, saved to Files on this iPhone.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .textCase(nil)
                    } footer: {
                        SectionFooter(text: "At least \(databaseByteCount.formatted(.byteCount(style: .file))), since it includes a full copy of the database.")
                    }
                    .listRowBackground(Color.surface)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if result == nil {
                    VStack(spacing: 8) {
                        if let errorText {
                            InlineMessage(text: errorText)
                        }
                        Button(action: startExport) {
                            if isExporting {
                                ProgressView()
                                    .tint(Color.onChampagne)
                            } else {
                                Text("Export")
                            }
                        }
                        .buttonStyle(.primary)
                    }
                    .padding()
                }
            }
            .navigationTitle(result == nil ? "Export a copy" : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close, action: close)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func close() {
        dismiss()
    }

    private func startExport() {
        guard !isExporting else { return }
        Task { await export() }
    }

    private func export() async {
        isExporting = true
        defer { isExporting = false }
        do {
            result = try await Exporter.export(
                dbPool: container.database.dbPool,
                exportsRoot: URL.documentsDirectory.appending(path: "exports", directoryHint: .isDirectory)
            )
            errorText = nil
        } catch {
            errorText = "Couldn't export: \(error.localizedDescription)"
        }
    }
}
