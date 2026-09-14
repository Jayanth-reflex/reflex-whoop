import XCTest
@testable import ReflexWhoop

final class TemperatureUnitTests: XCTestCase {
    func testReadingsConvert() {
        XCTAssertEqual(TemperatureUnit.fahrenheit.value(fromCelsius: 33.9), 93.02, accuracy: 0.0001)
        XCTAssertEqual(TemperatureUnit.fahrenheit.value(fromCelsius: 0), 32)
        XCTAssertEqual(TemperatureUnit.celsius.value(fromCelsius: 33.9), 33.9)
    }

    func testMatchingTheIPhoneFollowsItsTemperatureSetting() {
        XCTAssertEqual(TemperaturePreference.system.unit(locale: Locale(identifier: "en_IN")), .celsius)
        XCTAssertEqual(TemperaturePreference.system.unit(locale: Locale(identifier: "en_US")), .fahrenheit)
        // Settings › General › Language & Region › Temperature, set apart from the region.
        XCTAssertEqual(TemperaturePreference.system.unit(locale: Locale(identifier: "en_IN@mu=fahrenhe")), .fahrenheit)
    }

    func testAChosenUnitOverridesTheIPhone() {
        XCTAssertEqual(TemperaturePreference.celsius.unit(locale: Locale(identifier: "en_US")), .celsius)
        XCTAssertEqual(TemperaturePreference.fahrenheit.unit(locale: Locale(identifier: "en_IN")), .fahrenheit)
    }
}
