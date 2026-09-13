import SwiftUI

/// Shown when several overnight signals moved away from normal together, the
/// way they often do before someone feels ill. Says what moved, and that it's
/// a pattern, not a diagnosis.
struct IllnessCard: View {
    let signals: [Metric]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(IllnessCopy.title, systemImage: "exclamationmark.triangle")
                .font(.headline)
                .foregroundStyle(Color.sunstone)
            Text("\(IllnessCopy.whatMoved(signals)) \(IllnessCopy.context)")
            Text(IllnessCopy.caveat)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}
