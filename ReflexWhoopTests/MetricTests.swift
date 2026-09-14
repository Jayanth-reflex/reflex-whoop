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
        XCTAssertEqual(Metric.recovery.formatted(85.4, temperature: .celsius, locale: posix), "85")
        XCTAssertEqual(Metric.strain.formatted(0.506, temperature: .celsius, locale: posix), "0.5")
        XCTAssertEqual(Metric.breathingRate.formatted(13.16, temperature: .celsius, locale: posix), "13.2")
        XCTAssertEqual(Metric.heartRateVariability.formatted(74.14, temperature: .celsius, locale: posix), "74")
    }

    func testValueWithUnit() {
        XCTAssertEqual(Metric.recovery.formattedWithUnit(85, temperature: .celsius, locale: posix), "85%")
        XCTAssertEqual(Metric.heartRateVariability.formattedWithUnit(74, temperature: .celsius, locale: posix), "74 ms")
        XCTAssertEqual(Metric.strain.formattedWithUnit(0.5, temperature: .celsius, locale: posix), "0.5")
    }

    /// Stored in Celsius; shown in whichever unit the person chose. Only
    /// temperature changes with the setting.
    func testSkinTemperatureFollowsTheTemperatureUnit() {
        XCTAssertEqual(Metric.skinTemperature.formattedWithUnit(33.863667, temperature: .celsius, locale: posix), "33.9 °C")
        XCTAssertEqual(Metric.skinTemperature.formattedWithUnit(33.863667, temperature: .fahrenheit, locale: posix), "93.0 °F")
        XCTAssertEqual(Metric.skinTemperature.displayValue(33.863667, temperature: .fahrenheit), 92.954, accuracy: 0.001)
        XCTAssertEqual(Metric.skinTemperature.unit(.fahrenheit), "°F")
        XCTAssertEqual(Metric.restingHeartRate.formattedWithUnit(52, temperature: .fahrenheit, locale: posix), "52 bpm")
        XCTAssertEqual(Metric.restingHeartRate.displayValue(52, temperature: .fahrenheit), 52)
    }

    /// Like WHOOP, skin temperature is read as its change from normal: signed,
    /// and converted without Fahrenheit's 32° offset, since it's a difference.
    func testDifferenceFromNormal() {
        let normal = NormalRange(mean: 33.88, standardDeviation: 0.43)
        let skin = Metric.skinTemperature
        XCTAssertEqual(skin.formattedDifferenceWithUnit(34.37, from: normal, temperature: .celsius, locale: posix), "+0.5 °C")
        XCTAssertEqual(skin.formattedDifferenceWithUnit(34.37, from: normal, temperature: .fahrenheit, locale: posix), "+0.9 °F")
        XCTAssertEqual(skin.formattedDifferenceWithUnit(33.58, from: normal, temperature: .celsius, locale: posix), "\u{2212}0.3 °C")
        XCTAssertEqual(skin.formattedDifferenceWithUnit(33.863667, from: normal, temperature: .celsius, locale: posix), "0.0 °C", "no sign on a change that rounds to nothing")
        XCTAssertEqual(skin.formattedDifference(34.37, from: normal, temperature: .celsius, locale: posix), "+0.5")
    }

    func testOnlySkinTemperatureLeadsWithItsDifference() {
        XCTAssertEqual(Metric.allCases.filter(\.leadsWithDifferenceFromNormal), [.skinTemperature])
    }

    func testSections() {
        XCTAssertEqual(Metric.Section.scores.metrics, [.recovery, .strain, .sleepPerformance])
        XCTAssertEqual(Metric.Section.overnight.metrics, [.heartRateVariability, .restingHeartRate, .breathingRate, .skinTemperature, .bloodOxygen])
    }
}
