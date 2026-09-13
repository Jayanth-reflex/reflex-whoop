import XCTest
@testable import ReflexWhoop

final class SourceStatePresentationTests: XCTestCase {
    func testStatusTextIsPlainWords() {
        XCTAssertEqual(SourceState.active(lastSuccess: nil).statusText, "Connected")
        XCTAssertEqual(SourceState.notConfigured.statusText, "Not set up")
        XCTAssertEqual(SourceState.unauthorized.statusText, "Signed out")
        XCTAssertEqual(SourceState.inactive(reason: "403").statusText, "Membership ended")
        XCTAssertEqual(SourceState.unreachable(reason: "offline").statusText, "Can't reach WHOOP")
    }
}
