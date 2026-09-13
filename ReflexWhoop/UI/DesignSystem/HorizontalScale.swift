import Foundation

/// Maps values onto a horizontal drawing: the domain runs from `inset` to
/// `width - inset`, and values outside it are held at the ends. The inset
/// leaves room for a marker drawn at either end.
struct HorizontalScale {
    let domain: ClosedRange<Double>
    let inset: Double
    let width: Double

    /// Where `value` falls along the domain, from 0 to 1. This is also the
    /// `scalePosition` that puts a label under it.
    func position(_ value: Double) -> Double {
        let span = domain.upperBound - domain.lowerBound
        guard span > 0 else { return 0 }
        return (min(max(value, domain.lowerBound), domain.upperBound) - domain.lowerBound) / span
    }

    func x(_ value: Double) -> Double {
        inset + position(value) * (width - 2 * inset)
    }
}
