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

    func testEmptyWhenNothingIsHeld() {
        XCTAssertEqual(TodayLayout.choose(hasScores: false, whoop: .notConfigured, hasBandHistory: false), .empty)
        XCTAssertEqual(TodayLayout.choose(hasScores: false, whoop: ended, hasBandHistory: false), .empty)
    }
}
