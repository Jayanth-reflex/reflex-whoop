import SwiftUI

extension ReadingStatus {
    /// Sunstone for unusual readings; everything else stays secondary, so
    /// colour draws the eye only where something is off.
    var foreground: AnyShapeStyle {
        isUnusual ? AnyShapeStyle(Color.sunstone) : AnyShapeStyle(.secondary)
    }
}
