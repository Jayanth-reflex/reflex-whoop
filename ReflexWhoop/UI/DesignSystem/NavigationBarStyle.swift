import SwiftUI

/// Large navigation titles in New York, and ivory titles throughout.
///
/// SwiftUI has no API for navigation title fonts, so this sets them once on
/// UIKit's navigation bar appearance.
enum NavigationBarStyle {
    @MainActor
    static func apply() {
        let ivory = UIColor(resource: .ivory)
        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = [.font: largeTitleFont(), .foregroundColor: ivory]
        bar.titleTextAttributes = [.foregroundColor: ivory]
    }

    /// Built at the default content size and scaled through `UIFontMetrics`,
    /// so the title keeps following Dynamic Type after launch.
    private static func largeTitleFont() -> UIFont {
        let defaultSize = UITraitCollection(preferredContentSizeCategory: .large)
        let system = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .largeTitle, compatibleWith: defaultSize)
        let serif = system.withDesign(.serif) ?? system
        return UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: UIFont(descriptor: serif, size: 0))
    }
}
