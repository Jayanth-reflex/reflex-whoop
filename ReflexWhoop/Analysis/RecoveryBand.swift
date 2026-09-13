import Foundation

/// WHOOP's recovery bands, on WHOOP's own edges so a score reads the same here
/// as it does in WHOOP's app.
enum RecoveryBand: CaseIterable, Equatable {
    case low, moderate, high

    /// WHOOP's recovery score runs 0–100.
    static let scale = 0.0...100.0

    static let illnessNote = "Several signals are off from your normal."

    init(score: Double) {
        self = Self.allCases.last { score >= $0.lowerBound } ?? .low
    }

    /// Where the band starts. It runs up to the next band's start.
    var lowerBound: Double {
        switch self {
        case .low: Self.scale.lowerBound
        case .moderate: 34
        case .high: 67
        }
    }

    var upperBound: Double {
        Self.allCases.first { $0.lowerBound > lowerBound }?.lowerBound ?? Self.scale.upperBound
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
