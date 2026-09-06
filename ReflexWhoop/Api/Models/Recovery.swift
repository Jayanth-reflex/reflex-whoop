import Foundation

/// `GET /v2/recovery` record, keyed by `cycle_id` (one recovery per cycle).
struct Recovery: Decodable {
    let cycleId: Int64
    let sleepId: String?
    let userId: Int64
    let createdAt: Date
    let updatedAt: Date
    let scoreState: ScoreState
    let score: Score?

    struct Score: Decodable {
        let userCalibrating: Bool
        let recoveryScore: Double
        let restingHeartRate: Double
        let hrvRmssdMilli: Double
        let spo2Percentage: Double?
        let skinTempCelsius: Double?

        enum CodingKeys: String, CodingKey {
            case userCalibrating = "user_calibrating"
            case recoveryScore = "recovery_score"
            case restingHeartRate = "resting_heart_rate"
            case hrvRmssdMilli = "hrv_rmssd_milli"
            case spo2Percentage = "spo2_percentage"
            case skinTempCelsius = "skin_temp_celsius"
        }
    }

    enum CodingKeys: String, CodingKey {
        case cycleId = "cycle_id"
        case sleepId = "sleep_id"
        case userId = "user_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case scoreState = "score_state"
        case score
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cycleId = try c.decode(Int64.self, forKey: .cycleId)
        sleepId = try c.decodeIfPresent(String.self, forKey: .sleepId)
        userId = try c.decode(Int64.self, forKey: .userId)
        createdAt = try c.decode(WhoopDate.self, forKey: .createdAt).date
        updatedAt = try c.decode(WhoopDate.self, forKey: .updatedAt).date
        scoreState = try c.decode(ScoreState.self, forKey: .scoreState)
        score = try c.decodeIfPresent(Score.self, forKey: .score)
    }
}
