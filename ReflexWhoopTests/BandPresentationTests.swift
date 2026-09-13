import XCTest
@testable import ReflexWhoop

final class BandPresentationTests: XCTestCase {
    func testNoRecorderIsIdle() {
        XCTAssertEqual(BandPresentation(connection: nil), .idle)
    }

    func testReadyIsLive() {
        XCTAssertEqual(BandPresentation(connection: .ready), .live)
    }

    /// Every step between asking for the band and hearing from it reads as
    /// looking, including a drop the connection will retry by itself.
    func testInBetweenStatesAreSearching() {
        let states: [BandConnection.ConnectionState] = [.idle, .scanning, .connecting, .discoveringServices, .subscribing, .disconnected("timeout")]
        for state in states {
            XCTAssertEqual(BandPresentation(connection: state), .searching, "\(state)")
        }
    }

    func testEachUnavailabilityHasItsOwnFix() {
        XCTAssertEqual(BandPresentation(connection: .unavailable(.poweredOff)), .bluetoothOff)
        XCTAssertEqual(BandPresentation(connection: .unavailable(.unauthorized)), .bluetoothDenied)
        XCTAssertEqual(BandPresentation(connection: .unavailable(.unsupported)), .unsupported)
    }
}
