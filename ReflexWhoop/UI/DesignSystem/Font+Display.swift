import SwiftUI

extension Font {
    /// New York, for large titles, headlines and onboarding. Everything else
    /// stays on SF text styles.
    static func display(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .serif, weight: weight)
    }
}
