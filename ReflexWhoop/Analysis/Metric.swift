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

    var unit: String {
        switch self {
        case .recovery, .sleepPerformance, .bloodOxygen: "%"
        case .strain: ""
        case .heartRateVariability: "ms"
        case .restingHeartRate: "bpm"
        case .breathingRate: "/min"
        case .skinTemperature: "°C"
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

    func formatted(_ value: Double, locale: Locale = .current) -> String {
        value.formatted(.number.precision(.fractionLength(fractionDigits)).locale(locale))
    }

    /// The unit as it follows a number: "%" directly, anything else after a space.
    var unitSuffix: String {
        switch unit {
        case "": ""
        case "%": "%"
        default: " \(unit)"
        }
    }

    func formattedWithUnit(_ value: Double, locale: Locale = .current) -> String {
        formatted(value, locale: locale) + unitSuffix
    }

    init?(column: String) {
        guard let match = Self.allCases.first(where: { $0.column == column }) else { return nil }
        self = match
    }
}
