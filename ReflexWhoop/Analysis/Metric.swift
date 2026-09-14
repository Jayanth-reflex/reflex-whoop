import Foundation

/// The daily metrics the app shows, and what a screen needs to present one.
///
/// Readiness is deliberately not here: it is hidden until its sleep-debt input
/// is rebuilt (docs/DECISIONS.md, "Readiness hidden").
enum Metric: String, CaseIterable, Identifiable, Hashable {
    case recovery, strain, sleepPerformance
    case heartRateVariability, restingHeartRate, breathingRate, skinTemperature, bloodOxygen

    enum Section: CaseIterable {
        case scores, overnight

        /// This section's metrics, in display order.
        var metrics: [Metric] {
            Metric.allCases.filter { $0.section == self }
        }
    }

    var id: String { rawValue }

    /// The `daily_metrics` column, which is also the `baselines.metric` key.
    var column: String {
        switch self {
        case .recovery: "recovery_score"
        case .strain: "day_strain"
        case .sleepPerformance: "sleep_performance_percentage"
        case .heartRateVariability: "hrv_rmssd_milli"
        case .restingHeartRate: "resting_heart_rate"
        case .breathingRate: "respiratory_rate"
        case .skinTemperature: "skin_temp_celsius"
        case .bloodOxygen: "spo2_percentage"
        }
    }

    var label: String {
        switch self {
        case .recovery: "Recovery"
        case .strain: "Strain"
        case .sleepPerformance: "Sleep performance"
        case .heartRateVariability: "Heart rate variability"
        case .restingHeartRate: "Resting heart rate"
        case .breathingRate: "Breathing rate"
        case .skinTemperature: "Skin temperature"
        case .bloodOxygen: "Blood oxygen"
        }
    }

    /// Short enough for a navigation bar title.
    var shortLabel: String { self == .heartRateVariability ? "HRV" : label }

    /// The unit shown after a value. Only temperature follows `temperature`.
    func unit(_ temperature: TemperatureUnit) -> String {
        switch self {
        case .recovery, .sleepPerformance, .bloodOxygen: "%"
        case .strain: ""
        case .heartRateVariability: "ms"
        case .restingHeartRate: "bpm"
        case .breathingRate: "/min"
        case .skinTemperature: temperature.symbol
        }
    }

    var fractionDigits: Int {
        switch self {
        case .strain, .breathingRate, .skinTemperature, .bloodOxygen: 1
        case .recovery, .sleepPerformance, .heartRateVariability, .restingHeartRate: 0
        }
    }

    var section: Section {
        switch self {
        case .recovery, .strain, .sleepPerformance: .scores
        case .heartRateVariability, .restingHeartRate, .breathingRate, .skinTemperature, .bloodOxygen: .overnight
        }
    }

    /// Whether `BaselineEngine` keeps a normal range for this metric.
    var hasNormalRange: Bool { BaselineEngine.metrics.contains(column) }

    /// Like WHOOP, skin temperature is read as its change from the person's
    /// normal: the number itself varies too much between people to mean much.
    var leadsWithDifferenceFromNormal: Bool { self == .skinTemperature }

    /// A stored value in the unit it's shown in, for plotting.
    func displayValue(_ value: Double, temperature: TemperatureUnit) -> Double {
        self == .skinTemperature ? temperature.value(fromCelsius: value) : value
    }

    func formatted(_ value: Double, temperature: TemperatureUnit, locale: Locale = .current) -> String {
        formatted(displayValue: displayValue(value, temperature: temperature), locale: locale)
    }

    /// A value already in the unit it's shown in, such as a chart position.
    func formatted(displayValue: Double, locale: Locale = .current) -> String {
        displayValue.formatted(.number.precision(.fractionLength(fractionDigits)).locale(locale))
    }

    /// The unit as it follows a number: "%" directly, anything else after a space.
    func unitSuffix(_ temperature: TemperatureUnit) -> String {
        switch unit(temperature) {
        case "": ""
        case "%": "%"
        case let unit: " \(unit)"
        }
    }

    func formattedWithUnit(_ value: Double, temperature: TemperatureUnit, locale: Locale = .current) -> String {
        formatted(value, temperature: temperature, locale: locale) + unitSuffix(temperature)
    }

    /// How far `value` is from the middle of `range`, signed: "+0.5". A change
    /// that rounds to nothing has no sign.
    func formattedDifference(_ value: Double, from range: NormalRange, temperature: TemperatureUnit, locale: Locale = .current) -> String {
        // Both ends converted, so Fahrenheit's 32° offset cancels out.
        let difference = displayValue(value, temperature: temperature) - displayValue(range.mean, temperature: temperature)
        let step = pow(10, Double(fractionDigits))
        let rounded = (difference * step).rounded() / step
        return (rounded == 0 ? 0 : rounded)
            .formatted(.number.precision(.fractionLength(fractionDigits)).sign(strategy: .always(includingZero: false)).locale(locale))
            .replacing("-", with: "\u{2212}")
    }

    func formattedDifferenceWithUnit(_ value: Double, from range: NormalRange, temperature: TemperatureUnit, locale: Locale = .current) -> String {
        formattedDifference(value, from: range, temperature: temperature, locale: locale) + unitSuffix(temperature)
    }

    init?(column: String) {
        guard let match = Self.allCases.first(where: { $0.column == column }) else { return nil }
        self = match
    }
}
