import SwiftUI

/// Explains that WHOOP stopped sending scores, and what still works.
struct MembershipEndedCard: View {
    let archive: ArchiveSummary

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text("WHOOP membership ended")
                    .font(.headline)
                detail
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "info.circle")
                .foregroundStyle(Color.sunstone)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var detail: Text {
        if let lastDate = archive.lastDate {
            Text("Recovery, sleep and strain stopped after \(lastDate, format: .dateTime.day().month(.wide)). Your band still records heart rate, and all ^[\(archive.dayCount) day](inflect: true) before that stay here.")
        } else {
            Text("Recovery, sleep and strain have stopped. Your band still records heart rate.")
        }
    }
}
