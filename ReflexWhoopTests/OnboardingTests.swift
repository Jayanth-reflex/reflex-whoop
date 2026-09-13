import XCTest
@testable import ReflexWhoop

final class OnboardingTests: XCTestCase {
    func testOnlyAFreshInstallSeesTheFlow() {
        XCTAssertTrue(Onboarding.shouldPresent(hasCompleted: false, archiveIsEmpty: true, hasWhoopAccount: false))
    }

    func testFinishingTheFlowEndsIt() {
        XCTAssertFalse(Onboarding.shouldPresent(hasCompleted: true, archiveIsEmpty: true, hasWhoopAccount: false))
    }

    /// Installs from before the flow existed already have data or an account.
    func testExistingInstallsNeverSeeIt() {
        XCTAssertFalse(Onboarding.shouldPresent(hasCompleted: false, archiveIsEmpty: false, hasWhoopAccount: false))
        XCTAssertFalse(Onboarding.shouldPresent(hasCompleted: false, archiveIsEmpty: true, hasWhoopAccount: true))
    }
}
