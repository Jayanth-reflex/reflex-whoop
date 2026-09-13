import SwiftUI

/// The account's state, centred: a word, its dot, and what it means.
struct WhoopStatusHeader: View {
    let state: SourceState
    let archive: ArchiveSummary?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "icloud")
                .font(.title)
                .frame(width: 72, height: 72)
                .background(Color.surface, in: .circle)
                .accessibilityHidden(true)
            StatusLabel(text: state.statusText, tint: state.tint)
                .font(.title2.weight(.semibold))
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var detail: String? {
        switch state {
        case .active(let lastSuccess):
            lastSuccess.map { "Last synced \($0.formatted(.relative(presentation: .named)))" } ?? "Not synced yet"
        case .unreachable:
            "The last sync didn't get through. Your history here is unaffected."
        case .inactive:
            if let lastDay = archive?.lastDay, let date = RecordDAO.date(forDay: lastDay) {
                "WHOOP stopped sending new data after \(date.formatted(.dateTime.day().month(.wide).recordedDay()))."
            } else {
                "WHOOP has stopped sending new data."
            }
        case .unauthorized:
            "Sign in again to bring in new days. Everything already here stays."
        case .notConfigured:
            nil
        }
    }
}
