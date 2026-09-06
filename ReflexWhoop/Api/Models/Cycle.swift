import Foundation

/// `GET /v2/cycle` record. `end` is `nil` while the physiological cycle is ongoing.
struct Cycle: Decodable {
    let id: Int64
    let userId: Int64
    let createdAt: Date
    let updatedAt: Date
    let start: Date
    let end: Date?
    let timezoneOffset: String
    let scoreState: ScoreState
    let score: Score?

    struct Score: Decodable {
        let strain: Double
        let kilojoule: Double
        let averageHeartRate: Int
        let maxHeartRate: Int

        enum CodingKeys: String, CodingKey {
            case strain, kilojoule
            case averageHeartRate = "average_heart_rate"
            case maxHeartRate = "max_heart_rate"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case start, end
        case timezoneOffset = "timezone_offset"
        case scoreState = "score_state"
        case score
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        userId = try c.decode(Int64.self, forKey: .userId)
        createdAt = try c.decode(WhoopDate.self, forKey: .createdAt).date
        updatedAt = try c.decode(WhoopDate.self, forKey: .updatedAt).date
        start = try c.decode(WhoopDate.self, forKey: .start).date
        end = try c.decodeIfPresent(WhoopOptionalDate.self, forKey: .end)?.date
        timezoneOffset = try c.decode(String.self, forKey: .timezoneOffset)
        scoreState = try c.decode(ScoreState.self, forKey: .scoreState)
        score = try c.decodeIfPresent(Score.self, forKey: .score)
    }
}
