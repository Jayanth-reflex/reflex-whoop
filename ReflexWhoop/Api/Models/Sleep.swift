import Foundation

/// `GET /v2/activity/sleep` record. `id` is a v2 UUID; `v1Id` is kept for
/// cross-referencing data collected before the v1→v2 migration.
struct Sleep: Decodable {
    let id: String
    let v1Id: Int64?
    let userId: Int64
    let createdAt: Date
    let updatedAt: Date
    let start: Date
    let end: Date
    let timezoneOffset: String
    let nap: Bool
    let scoreState: ScoreState
    let score: Score?

    struct Score: Decodable {
        let stageSummary: StageSummary
        let sleepNeeded: SleepNeeded
        let respiratoryRate: Double?
        let sleepPerformancePercentage: Double?
        let sleepConsistencyPercentage: Double?
        let sleepEfficiencyPercentage: Double?

        enum CodingKeys: String, CodingKey {
            case stageSummary = "stage_summary"
            case sleepNeeded = "sleep_needed"
            case respiratoryRate = "respiratory_rate"
            case sleepPerformancePercentage = "sleep_performance_percentage"
            case sleepConsistencyPercentage = "sleep_consistency_percentage"
            case sleepEfficiencyPercentage = "sleep_efficiency_percentage"
        }
    }

    struct StageSummary: Decodable {
        let totalInBedTimeMilli: Int
        let totalAwakeTimeMilli: Int
        let totalNoDataTimeMilli: Int
        let totalLightSleepTimeMilli: Int
        let totalSlowWaveSleepTimeMilli: Int
        let totalRemSleepTimeMilli: Int
        let sleepCycleCount: Int
        let disturbanceCount: Int

        enum CodingKeys: String, CodingKey {
            case totalInBedTimeMilli = "total_in_bed_time_milli"
            case totalAwakeTimeMilli = "total_awake_time_milli"
            case totalNoDataTimeMilli = "total_no_data_time_milli"
            case totalLightSleepTimeMilli = "total_light_sleep_time_milli"
            case totalSlowWaveSleepTimeMilli = "total_slow_wave_sleep_time_milli"
            case totalRemSleepTimeMilli = "total_rem_sleep_time_milli"
            case sleepCycleCount = "sleep_cycle_count"
            case disturbanceCount = "disturbance_count"
        }
    }

    struct SleepNeeded: Decodable {
        let baselineMilli: Int
        let needFromSleepDebtMilli: Int
        let needFromRecentStrainMilli: Int
        let needFromRecentNapMilli: Int

        enum CodingKeys: String, CodingKey {
            case baselineMilli = "baseline_milli"
            case needFromSleepDebtMilli = "need_from_sleep_debt_milli"
            case needFromRecentStrainMilli = "need_from_recent_strain_milli"
            case needFromRecentNapMilli = "need_from_recent_nap_milli"
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
        case nap
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
        nap = try c.decode(Bool.self, forKey: .nap)
        scoreState = try c.decode(ScoreState.self, forKey: .scoreState)
        score = try c.decodeIfPresent(Score.self, forKey: .score)
    }
}
