import Foundation

extension FormatStyle where Self == FloatingPointFormatStyle<Double> {
    /// Heart rate in whole beats per minute, without the unit.
    static var bpm: Self {
        .number.precision(.fractionLength(0))
    }
}

extension FormatStyle where Self == Duration.UnitsFormatStyle {
    /// "7h 32m": lengths of sleep and recording.
    static var hoursMinutes: Self {
        .units(allowed: [.hours, .minutes], width: .narrow)
    }
}
