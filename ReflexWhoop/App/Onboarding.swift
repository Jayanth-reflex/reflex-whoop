import Foundation

/// The first-run flow exists to get a new install to its first data. An
/// install that already holds data or has a WHOOP account set up, including
/// every install from before the flow existed, never sees it.
enum Onboarding {
    static let completedKey = "hasCompletedOnboarding"

    static func shouldPresent(hasCompleted: Bool, archiveIsEmpty: Bool, hasWhoopAccount: Bool) -> Bool {
        !hasCompleted && archiveIsEmpty && !hasWhoopAccount
    }
}
