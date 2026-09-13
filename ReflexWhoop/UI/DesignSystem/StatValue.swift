import SwiftUI

/// A small labelled statistic: a caption above a value and its unit.
struct StatValue: View {
    let title: String
    let value: String
    var unit = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(Text(value).font(.title2).bold())\(Text(unit.isEmpty ? "" : " \(unit)").font(.subheadline).foregroundStyle(.secondary))")
        }
        .accessibilityElement(children: .combine)
    }
}
