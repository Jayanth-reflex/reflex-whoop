import Foundation

/// The unit a temperature is shown in. Readings are always stored in Celsius,
/// as WHOOP sends them; this only changes what's on screen.
enum TemperatureUnit: Equatable {
    case celsius, fahrenheit

    /// The unit `locale` prefers, including the iPhone's own Temperature
    /// setting when it differs from the region's.
    init(locale: Locale) {
        self = UnitTemperature(forLocale: locale) == .fahrenheit ? .fahrenheit : .celsius
    }

    var symbol: String {
        switch self {
        case .celsius: "°C"
        case .fahrenheit: "°F"
        }
    }

    /// A reading of `celsius` degrees in this unit.
    func value(fromCelsius celsius: Double) -> Double {
        switch self {
        case .celsius: celsius
        case .fahrenheit: celsius * 9 / 5 + 32
        }
    }
}
