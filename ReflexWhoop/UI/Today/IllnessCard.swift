import SwiftUI

/// Shown when several overnight signals moved away from normal together, the
/// way they often do before someone feels ill. Says what moved, and that it's
/// a pattern, not a diagnosis.
struct IllnessCard: View {
    let signals: [Metric]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Your body may be fighting something", systemImage: "exclamationmark.triangle")
                .font(.headline)
                .foregroundStyle(Color.sunstone)
            Text("\(whatMoved) That pattern often shows up a day or two before feeling ill.")
            Text("A pattern in your numbers, not a diagnosis.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private var whatMoved: String {
        guard !signals.isEmpty else { return "Several signals moved away from your normal together." }
        let names = signals.map { $0.label.lowercased() }.formatted(.list(type: .and))
        return "\(names.prefix(1).uppercased())\(names.dropFirst()) all moved away from your normal together."
    }
}
