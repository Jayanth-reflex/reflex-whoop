import XCTest
@testable import ReflexWhoop

final class IllnessCopyTests: XCTestCase {
    private let english = Locale(identifier: "en_US")

    func testNamesTheSignalsThatMoved() {
        XCTAssertEqual(
            IllnessCopy.whatMoved([.breathingRate, .restingHeartRate, .heartRateVariability], locale: english),
            "Breathing rate, resting heart rate, and heart rate variability all moved away from your normal together."
        )
    }

    func testFallsBackWhenTheSignalsAreUnknown() {
        XCTAssertEqual(IllnessCopy.whatMoved([], locale: english), "Several signals moved away from your normal together.")
    }
}
