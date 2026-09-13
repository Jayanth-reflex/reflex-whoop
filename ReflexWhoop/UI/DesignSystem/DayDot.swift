import SwiftUI

/// A day's dot on a history chart, ringed in the card colour so it stays
/// distinct where it sits on the line or the band.
struct DayDot: View {
    let isUnusual: Bool
    let isLatest: Bool

    private var diameter: Double {
        if isLatest { 12 } else if isUnusual { 9 } else { 4.5 }
    }

    var body: some View {
        Circle()
            .fill(isUnusual ? AnyShapeStyle(Color.sunstone) : AnyShapeStyle(.primary))
            .stroke(Color.surface, lineWidth: isLatest || isUnusual ? 2 : 0)
            .frame(width: diameter, height: diameter)
    }
}
