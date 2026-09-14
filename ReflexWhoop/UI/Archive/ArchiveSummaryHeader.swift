import SwiftUI

/// How much the archive holds: days, the span they cover, recordings,
/// readings and the space it takes.
struct ArchiveSummaryHeader: View {
    let archive: ArchiveSummary
    let byteCount: Int64

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                HeroValue(archive.dayCount.formatted(), unit: archive.dayCount == 1 ? "day" : "days", scale: 1.9)
                if let span {
                    Text(span)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)

            StatRow {
                ArchiveTile(value: archive.bleSessionCount.formatted(), caption: "Recordings")
                ArchiveTile(value: archive.bleSampleCount.formatted(.number.notation(.compactName)), caption: "Readings")
                ArchiveTile(value: byteCount.formatted(.byteCount(style: .file)), caption: "On disk")
            }
        }
    }

    private var span: String? {
        guard let first = archive.firstDate, let last = archive.lastDate else { return nil }
        let start = first.formatted(.dateTime.day().month(.wide))
        let end = last.formatted(.dateTime.day().month(.wide).year())
        return "\(start) – \(end)"
    }
}
