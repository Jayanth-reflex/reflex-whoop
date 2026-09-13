import SwiftUI

/// Where a label sits along a `ScaleLabelLayout`, from 0 to 1.
struct ScalePosition: LayoutValueKey {
    static let defaultValue = 0.0
}

extension View {
    func scalePosition(_ fraction: Double) -> some View {
        layoutValue(key: ScalePosition.self, value: fraction)
    }
}
