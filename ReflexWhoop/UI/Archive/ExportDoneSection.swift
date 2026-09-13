import SwiftUI

/// Where the finished copy is, with ways to share it or open it in Files.
struct ExportDoneSection: View {
    let result: Exporter.Result

    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
            VStack(spacing: 14) {
                Image(systemName: "checkmark")
                    .font(.title.bold())
                    .foregroundStyle(Color.onChampagne)
                    .frame(width: 64, height: 64)
                    .background(Color.accent, in: .circle)
                    .accessibilityHidden(true)
                Text("Copy saved")
                    .font(.title2.weight(.semibold))
                Text("Files › On My iPhone › ReflexWhoop › exports › \(result.directory.lastPathComponent)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text("\(result.manifest.rowCounts.values.reduce(0, +).formatted()) rows · \(Int64(result.manifest.byteCounts.values.reduce(0, +)).formatted(.byteCount(style: .file)))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                VStack(spacing: 10) {
                    ShareLink(item: result.directory) {
                        Label("Share…", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.primary)
                    Button("Show in Files", systemImage: "folder", action: showInFiles)
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity)
        }
        .listRowBackground(Color.clear)
    }

    /// The Files app opens straight to a folder given its path under this scheme.
    private func showInFiles() {
        guard let url = URL(string: "shareddocuments://\(result.directory.path(percentEncoded: true))") else { return }
        openURL(url)
    }
}
