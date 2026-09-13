import XCTest
@testable import ReflexWhoop

final class MetricTests: XCTestCase {
    private let posix = Locale(identifier: "en_US_POSIX")

    func testReadinessIsNotAMetric() {
        XCTAssertNil(Metric(column: "readiness_score"))
        XCTAssertFalse(Metric.allCases.map(\.column).contains("readiness_score"))
    }

    func testColumnRoundTrip() {
        for metric in Metric.allCases {
            XCTAssertEqual(Metric(column: metric.column), metric)
        }
    }

    func testNormalRangesExistExactlyForBaselinedMetrics() {
        let baselined = Set(Metric.allCases.filter(\.hasNormalRange).map(\.column))
        XCTAssertEqual(baselined, Set(BaselineEngine.metrics))
    }

    func testFormatting() {
        XCTAssertEqual(Metric.recovery.formatted(85.4, locale: posix), "85")
        XCTAssertEqual(Metric.strain.formatted(0.506, locale: posix), "0.5")
        XCTAssertEqual(Metric.breathingRate.formatted(13.16, locale: posix), "13.2")
        XCTAssertEqual(Metric.heartRateVariability.formatted(74.14, locale: posix), "74")
    }

    func testValueWithUnit() {
        XCTAssertEqual(Metric.recovery.formattedWithUnit(85, locale: posix), "85%")
        XCTAssertEqual(Metric.heartRateVariability.formattedWithUnit(74, locale: posix), "74 ms")
        XCTAssertEqual(Metric.strain.formattedWithUnit(0.5, locale: posix), "0.5")
    }

    func testSections() {
        XCTAssertEqual(Metric.Section.scores.metrics, [.recovery, .strain, .sleepPerformance])
        XCTAssertEqual(Metric.Section.overnight.metrics, [.heartRateVariability, .restingHeartRate, .breathingRate, .skinTemperature, .bloodOxygen])
    }
}
