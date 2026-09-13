import XCTest
@testable import ReflexWhoop

final class HeartRateWindowTests: XCTestCase {
    private func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

    func testKeepsOnlyTheSpan() {
        var window = HeartRateWindow(span: 60)
        window.append(bpm: 60, at: at(0))
        window.append(bpm: 70, at: at(30))
        window.append(bpm: 80, at: at(61))
        XCTAssertEqual(window.readings.map(\.bpm), [70, 80])
    }

    func testReadingExactlyAtTheEdgeIsKept() {
        var window = HeartRateWindow(span: 60)
        window.append(bpm: 60, at: at(0))
        window.append(bpm: 70, at: at(60))
        XCTAssertEqual(window.readings.count, 2)
    }

    func testRange() {
        var window = HeartRateWindow(span: 600)
        XCTAssertNil(window.bpmRange)
        window.append(bpm: 72, at: at(0))
        window.append(bpm: 59, at: at(1))
        window.append(bpm: 104, at: at(2))
        XCTAssertEqual(window.bpmRange, 59...104)
    }
}
