import Foundation

/// The first-run screens after Welcome, in the order they can appear.
enum OnboardingStep: Hashable {
    case sources, bluetooth, whoop, firstSync
}
