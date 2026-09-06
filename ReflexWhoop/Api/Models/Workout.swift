import Foundation

/// `GET /v2/activity/workout` record. `id` is a v2 UUID; `v1Id` is kept for
/// cross-referencing data collected before the v1→v2 migration.
struct Workout: Decodable {
    let id: String
    let v1Id: Int64?
    let userId: Int64
    let createdAt: Date
    let updatedAt: Date
    let start: Date
    let end: Date
    let timezoneOffset: String
    let sportName: String?
    let scoreState: ScoreState
    let score: Score?

    struct Score: Decodable {
        let strain: Double
        let averageHeartRate: Int
        let maxHeartRate: Int
        let kilojoule: Double
        let percentRecorded: Double?
        let distanceMeter: Double?
        let altitudeGainMeter: Double?
        let altitudeChangeMeter: Double?
        let zoneDurations: ZoneDurations?

        enum CodingKeys: String, CodingKey {
            case strain
            case averageHeartRate = "average_heart_rate"
            case maxHeartRate = "max_heart_rate"
            case kilojoule
            case percentRecorded = "percent_recorded"
            case distanceMeter = "distance_meter"
            case altitudeGainMeter = "altitude_gain_meter"
            case altitudeChangeMeter = "altitude_change_meter"
            case zoneDurations = "zone_durations"
        }
    }

    struct ZoneDurations: Decodable {
        let zoneZeroMilli: Int?
        let zoneOneMilli: Int?
        let zoneTwoMilli: Int?
        let zoneThreeMilli: Int?
        let zoneFourMilli: Int?
        let zoneFiveMilli: Int?

        enum CodingKeys: String, CodingKey {
            case zoneZeroMilli = "zone_zero_milli"
            case zoneOneMilli = "zone_one_milli"
            case zoneTwoMilli = "zone_two_milli"
            case zoneThreeMilli = "zone_three_milli"
            case zoneFourMilli = "zone_four_milli"
            case zoneFiveMilli = "zone_five_milli"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case v1Id = "v1_id"
        case userId = "user_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case start, end
        case timezoneOffset = "timezone_offset"
        case sportName = "sport_name"
        case scoreState = "score_state"
        case score
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        v1Id = try c.decodeIfPresent(Int64.self, forKey: .v1Id)
        userId = try c.decode(Int64.self, forKey: .userId)
        createdAt = try c.decode(WhoopDate.self, forKey: .createdAt).date
        updatedAt = try c.decode(WhoopDate.self, forKey: .updatedAt).date
        start = try c.decode(WhoopDate.self, forKey: .start).date
        end = try c.decode(WhoopDate.self, forKey: .end).date
        timezoneOffset = try c.decode(String.self, forKey: .timezoneOffset)
        sportName = try c.decodeIfPresent(String.self, forKey: .sportName)
        scoreState = try c.decode(ScoreState.self, forKey: .scoreState)
        score = try c.decodeIfPresent(Score.self, forKey: .score)
    }
}
