import XCTest
@testable import ReflexWhoop

final class MetricStatusSentenceTests: XCTestCase {
    private func point(_ value: Double, range: NormalRange?) -> MetricPoint {
        MetricPoint(day: "2026-09-12", date: .now, value: value, range: range)
    }

    /// Strain and sleep performance never get a normal range, so no amount of
    /// history would change a "not enough history" line under them.
    func testMetricsWithoutANormalRangeHaveNoStatus() {
        XCTAssertNil(point(12.4, range: nil).statusSentence(for: .strain))
        XCTAssertNil(point(72, range: nil).statusSentence(for: .sleepPerformance))
    }

    func testABaselinedMetricStillSaysWhenItsHistoryIsShort() {
        XCTAssertEqual(point(74, range: nil).statusSentence(for: .heartRateVariability), "Not enough history yet")
    }

    func testAgainstTheNormalRange() {
        let normal = NormalRange(mean: 64, standardDeviation: 5)
        XCTAssertEqual(point(66, range: normal).statusSentence(for: .heartRateVariability, locale: Locale(identifier: "en_US_POSIX")), "Within your normal of 59–69 ms")
        XCTAssertEqual(point(50, range: normal).statusSentence(for: .heartRateVariability, locale: Locale(identifier: "en_US_POSIX")), "Unusually low. Your normal is 59–69 ms")
    }
}
