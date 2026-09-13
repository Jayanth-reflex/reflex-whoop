import Foundation

extension Metric {
    /// What the metric is, in plain words, for its detail screen.
    var explanation: String {
        switch self {
        case .recovery:
            "WHOOP's 0–100 score for how ready your body is, worked out from your heart rate variability, resting heart rate, breathing rate and sleep."
        case .strain:
            "How much load your heart carried across the day, on WHOOP's 0–21 scale. The scale is logarithmic, so each point is harder to add than the one before."
        case .sleepPerformance:
            "The sleep you got as a share of the sleep WHOOP worked out you needed."
        case .heartRateVariability:
            "The variation in time between heartbeats while you sleep. Higher than your own normal usually means your body has recovered. It varies a lot between people, so it's only compared with you."
        case .restingHeartRate:
            "Your heart rate at rest while you sleep. It tends to rise above your normal with stress, illness, alcohol or hard training."
        case .breathingRate:
            "Breaths per minute while you sleep. It's usually very steady, so even a small change from your normal stands out."
        case .skinTemperature:
            "Your skin temperature while you sleep. What matters is the change from your own normal, not the number itself."
        case .bloodOxygen:
            "How much of your blood is carrying oxygen while you sleep. WHOOP doesn't get a reading every night."
        }
    }

    /// Where the number comes from.
    var source: String {
        switch section {
        case .scores: "WHOOP"
        case .overnight: "WHOOP, measured asleep"
        }
    }

    /// What one point on this metric's history is.
    var periodNoun: String {
        switch section {
        case .scores: "Days"
        case .overnight: "Nights"
        }
    }
}

extension Metric.Section {
    var title: String {
        switch self {
        case .scores: "Scores"
        case .overnight: "Overnight"
        }
    }
}
