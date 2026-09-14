import Foundation

extension TemperaturePreference {
    /// How the Temperature setting names this choice. Automatic says which
    /// unit it currently means.
    func title(locale: Locale) -> String {
        switch self {
        case .system: "Automatic (\(unit(locale: locale).symbol))"
        case .celsius: "Celsius (°C)"
        case .fahrenheit: "Fahrenheit (°F)"
        }
    }
}
