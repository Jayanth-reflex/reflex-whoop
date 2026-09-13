import Foundation

/// Plain names for `CorrelationEngine`'s predictors.
enum PredictorLabel {
    static func label(_ predictor: String) -> String {
        switch predictor {
        case "prior_day_strain": "Yesterday's strain"
        case "respiratory_rate": "Breathing rate"
        case "acute_chronic_ratio": "Training load balance"
        case "sleep_duration_hours": "Sleep duration"
        case "sleep_efficiency_pct": "Sleep efficiency"
        case "sleep_consistency_pct": "Sleep consistency"
        case "rem_sleep_pct": "REM sleep share"
        case "slow_wave_sleep_pct": "Deep sleep share"
        case "sleep_disturbance_count": "Sleep disturbances"
        default: predictor
        }
    }
}
