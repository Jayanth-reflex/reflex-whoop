import SwiftUI

/// A screen's one headline number: light New York numerals with a quieter
/// unit beside them.
struct HeroValue: View {
    let value: String
    let unit: String?

    /// Light serif at `.largeTitle` size times `scale`, following Dynamic Type.
    /// Figures stay proportional: tabular figures spread a light serif numeral
    /// too far apart at this size.
    @ScaledMetric private var numeralSize: Double

    init(_ value: String, unit: String?, scale: Double = 2.6) {
        self.value = value
        self.unit = unit
        _numeralSize = ScaledMetric(wrappedValue: 34 * scale, relativeTo: .largeTitle)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(value)
                .font(.system(size: numeralSize, weight: .light, design: .serif))
            if let unit {
                Text(unit)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
