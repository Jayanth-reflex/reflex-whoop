import XCTest
@testable import ReflexWhoop

final class MetricPointDisplayedTests: XCTestCase {
    /// Charts plot points in the unit they're shown in. The value and its
    /// normal range convert together, so a day is exactly as unusual as before.
    func testAPointInFahrenheitKeepsItsStatus() throws {
        let point = MetricPoint(day: "2026-09-12", date: .now, value: 34.9, range: NormalRange(mean: 33.88, standardDeviation: 0.43))
        let shown = point.displayed(for: .skinTemperature, temperature: .fahrenheit)
        let range = try XCTUnwrap(shown.range)

        XCTAssertEqual(shown.value, 94.82, accuracy: 0.0001)
        XCTAssertEqual(range.mean, 92.984, accuracy: 0.0001)
        XCTAssertEqual(range.standardDeviation, 0.774, accuracy: 0.0001)
        XCTAssertEqual(shown.status, point.status)
        XCTAssertEqual(shown.day, point.day)
    }

    func testOtherMetricsAreUnchanged() {
        let point = MetricPoint(day: "2026-09-12", date: .now, value: 74, range: NormalRange(mean: 64, standardDeviation: 5))
        XCTAssertEqual(point.displayed(for: .heartRateVariability, temperature: .fahrenheit), point)
    }
}
