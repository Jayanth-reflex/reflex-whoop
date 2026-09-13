import Foundation

/// WHOOP's recovery bands, on WHOOP's own edges so a score reads the same here
/// as it does in WHOOP's app.
enum RecoveryBand: Equatable {
    case low, moderate, high

    static let illnessNote = "Several signals are off from your normal."

    init(score: Double) {
        self = switch score {
        case ..<34: .low
        case ..<67: .moderate
        default: .high
        }
    }

    var label: String {
        switch self {
        case .low: "Low"
        case .moderate: "Moderate"
        case .high: "High"
        }
    }

    /// Never quotes sleep debt: the stored value is WHOOP's capped extra-need
    /// term, not debt owed (docs/DECISIONS.md, "Readiness hidden").
    var verdict: String {
        switch self {
        case .low: "Low recovery. Keep today easy."
        case .moderate: "Moderate recovery. Train, but keep something in reserve."
        case .high: "Well recovered. A good day to train hard."
        }
    }
}
