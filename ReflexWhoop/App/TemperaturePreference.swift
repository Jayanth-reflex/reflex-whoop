import Foundation

/// The Temperature setting: match the iPhone, or always one unit.
enum TemperaturePreference: String, CaseIterable, Identifiable {
    case system, celsius, fahrenheit

    static let key = "temperatureUnit"

    var id: String { rawValue }

    func unit(locale: Locale) -> TemperatureUnit {
        switch self {
        case .system: TemperatureUnit(locale: locale)
        case .celsius: .celsius
        case .fahrenheit: .fahrenheit
        }
    }
}
