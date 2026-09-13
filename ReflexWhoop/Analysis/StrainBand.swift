import Foundation

/// WHOOP's day strain categories on its 0–21 scale.
enum StrainBand: Equatable {
    case light, moderate, high, allOut

    static let scaleMaximum = 21.0

    init(strain: Double) {
        self = switch strain {
        case ..<10: .light
        case ..<14: .moderate
        case ..<18: .high
        default: .allOut
        }
    }

    var label: String {
        switch self {
        case .light: "Light"
        case .moderate: "Moderate"
        case .high: "High"
        case .allOut: "All out"
        }
    }
}
