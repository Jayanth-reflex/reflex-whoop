import XCTest
@testable import ReflexWhoop

final class ReadingStatusTests: XCTestCase {
    private let range = NormalRange(mean: 60, standardDeviation: 5)

    func testMissingValueIsNoReadingEvenWithARange() {
        XCTAssertEqual(ReadingStatus.classify(nil, against: range), .noReading)
    }

    func testValueWithoutRangeIsNotEnoughHistory() {
        XCTAssertEqual(ReadingStatus.classify(61, against: nil), .notEnoughHistory)
    }

    func testZeroSpreadCannotClassify() {
        XCTAssertEqual(ReadingStatus.classify(61, against: NormalRange(mean: 60, standardDeviation: 0)), .notEnoughHistory)
    }

    func testBoundaries() {
        XCTAssertEqual(ReadingStatus.classify(64.99, against: range), .within)
        XCTAssertEqual(ReadingStatus.classify(65, against: range), .above)
        XCTAssertEqual(ReadingStatus.classify(55, against: range), .below)
        XCTAssertEqual(ReadingStatus.classify(69.99, against: range), .above)
        XCTAssertEqual(ReadingStatus.classify(70, against: range), .unusuallyHigh)
        XCTAssertEqual(ReadingStatus.classify(50, against: range), .unusuallyLow)
    }

    /// The strip and the anomalies table must never disagree about "unusual".
    func testUnusualThresholdIsTheAnomalyEngines() {
        let atThreshold = range.mean + range.standardDeviation * AnomalyEngine.singleMetricThreshold
        XCTAssertTrue(ReadingStatus.classify(atThreshold, against: range).isUnusual)
        XCTAssertEqual(NormalRange.windowDays, AnomalyEngine.baselineWindow)
    }
}
