import Foundation

extension MetricPoint {
    /// Where this reading sits against the person's normal, in words. `nil`
    /// for a metric that never has a normal range, rather than a status that
    /// suggests more history would give it one.
    func statusSentence(for metric: Metric, temperature: TemperatureUnit, locale: Locale = .current) -> String? {
        guard metric.hasNormalRange else { return nil }
        guard let range else { return status.label }
        let usual = "\(metric.formatted(range.lowerBound, temperature: temperature, locale: locale))–\(metric.formattedWithUnit(range.upperBound, temperature: temperature, locale: locale))"
        return switch status {
        case .within, .above, .below: "\(status.label) of \(usual)"
        case .unusuallyHigh, .unusuallyLow: "\(status.label). Your normal is \(usual)"
        case .noReading, .notEnoughHistory: status.label
        }
    }
}
