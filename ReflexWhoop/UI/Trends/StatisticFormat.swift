import Foundation

/// How Patterns writes correlation statistics.
enum StatisticFormat {
    /// Signed to two places with a true minus sign: "+0.42", "−0.16".
    static func r(_ rho: Double) -> String {
        rho.formatted(.number.precision(.fractionLength(2)).sign(strategy: .always()))
            .replacing("-", with: "\u{2212}")
    }

    /// Two places, or "below 0.01" rather than a run of zeros.
    static func p(_ value: Double) -> String {
        value < 0.01 ? "below 0.01" : value.formatted(.number.precision(.fractionLength(2)))
    }
}
