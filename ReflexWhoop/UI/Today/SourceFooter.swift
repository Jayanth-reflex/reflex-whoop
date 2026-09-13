import SwiftUI

/// Where Today's scores come from, when they were last brought in, and
/// whether the account can still bring in more.
struct SourceFooter: View {
    let lastSyncedAt: Date?
    let whoop: SourceState

    var body: some View {
        Label(text, systemImage: "icloud")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
    }

    private var text: String {
        var parts = ["From WHOOP"]
        if let lastSyncedAt {
            parts.append("synced \(lastSyncedAt.formatted(.relative(presentation: .named)))")
        }
        switch whoop {
        case .active: break
        default: parts.append(whoop.statusText)
        }
        return parts.joined(separator: " · ")
    }
}
