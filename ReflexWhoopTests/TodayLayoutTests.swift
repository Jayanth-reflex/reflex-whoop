import XCTest
@testable import ReflexWhoop

final class TodayLayoutTests: XCTestCase {
    private let synced = SourceState.active(lastSuccess: nil)
    private let ended = SourceState.inactive(reason: "403")

    func testScoresWhenWhoopHasScoredADay() {
        XCTAssertEqual(TodayLayout.choose(hasScores: true, whoop: synced, hasBandHistory: true), .scores)
        XCTAssertEqual(TodayLayout.choose(hasScores: true, whoop: .unauthorized, hasBandHistory: false), .scores)
        XCTAssertEqual(TodayLayout.choose(hasScores: true, whoop: .unreachable(reason: "offline"), hasBandHistory: false), .scores)
    }

    /// Once a membership ends, the last scores are history, not today.
    func testEndedMembershipNeverShowsOldScoresAsToday() {
        XCTAssertEqual(TodayLayout.choose(hasScores: true, whoop: ended, hasBandHistory: true), .band(membershipEnded: true))
        XCTAssertEqual(TodayLayout.choose(hasScores: true, whoop: ended, hasBandHistory: false), .band(membershipEnded: true))
    }

    func testBandOnlyWithoutWhoopScores() {
        XCTAssertEqual(TodayLayout.choose(hasScores: false, whoop: .notConfigured, hasBandHistory: true), .band(membershipEnded: false))
    }

    /// Right after connecting, the account is set up but nothing has arrived:
    /// asking to connect it would be wrong.
    func testEmptyDescriptionFollowsTheAccount() {
        XCTAssertEqual(TodayLayout.emptyDescription(whoop: .notConfigured), "Connect your WHOOP account in Archive, or record from your band.")
        XCTAssertEqual(TodayLayout.emptyDescription(whoop: synced), "Your WHOOP history appears here as soon as it arrives.")
        XCTAssertEqual(TodayLayout.emptyDescription(whoop: .unreachable(reason: "offline")), "Your WHOOP history appears here as soon as it arrives.")
        XCTAssertEqual(TodayLayout.emptyDescription(whoop: .unauthorized), "Sign in to your WHOOP account in Archive, or record from your band.")
        XCTAssertEqual(TodayLayout.emptyDescription(whoop: ended), "WHOOP isn't sending new data. Record from your band to see your heart rate here.")
    }

    func testEmptyWhenNothingIsHeld() {
        XCTAssertEqual(TodayLayout.choose(hasScores: false, whoop: .notConfigured, hasBandHistory: false), .empty)
        XCTAssertEqual(TodayLayout.choose(hasScores: false, whoop: ended, hasBandHistory: false), .empty)
    }
}
