import Foundation
import GRDB

/// Upserts decoded API models into the normalized layer (Layer 2). Every function
/// follows the same shape:
///   1. compute a content hash over the fields that matter for analysis
///   2. skip the write entirely if the hash matches what's already stored
///   3. otherwise upsert, mark the affected day dirty, and track pending-score state
///
/// This is what makes the sync engine's 7-day re-scoring lookback cheap: re-fetching
/// a record that didn't change costs one hash comparison, not a write plus a
/// recompute of every derived metric that depends on that day.
enum RecordDAO {
    static let currentSource = "api"

    // MARK: - Day bucketing

    /// UTC calendar day of a timestamp, as `yyyy-MM-dd`. A known simplification:
    /// this ignores `timezone_offset`, so a record a few hours either side of local
    /// midnight can land on the "wrong" day relative to how WHOOP's own app buckets
    /// it. Acceptable for v1 trend/correlation analysis; revisit if day-boundary
    /// precision matters (e.g. exact sleep-debt accounting).
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func dayString(for date: Date) -> String {
        dayFormatter.string(from: date)
    }

    /// Inverse of `dayString(for:)`: midnight UTC of a `yyyy-MM-dd` day.
    static func date(forDay day: String) -> Date? {
        dayFormatter.date(from: day)
    }

    private static func markDirty(_ db: GRDB.Database, day: String, reason: String) throws {
        try db.execute(
            sql: """
            INSERT INTO dirty_days (day, reason, marked_at)
            VALUES (?, ?, ?)
            ON CONFLICT(day, reason) DO UPDATE SET marked_at = excluded.marked_at
            """,
            arguments: [day, reason, Int64(Date().timeIntervalSince1970)]
        )
    }

    private static func trackPendingScore(_ db: GRDB.Database, resource: String, recordId: String, scoreState: ScoreState) throws {
        switch scoreState {
        case .pendingScore:
            try db.execute(
                sql: """
                INSERT INTO pending_scores (resource, record_id, first_seen_at, attempts)
                VALUES (?, ?, ?, 0)
                ON CONFLICT(resource, record_id) DO NOTHING
                """,
                arguments: [resource, recordId, Int64(Date().timeIntervalSince1970)]
            )
        case .scored, .unscorable:
            try db.execute(
                sql: "DELETE FROM pending_scores WHERE resource = ? AND record_id = ?",
                arguments: [resource, recordId]
            )
        }
    }

    private static func existingHash(_ db: GRDB.Database, table: String, idColumn: String, id: some DatabaseValueConvertible) throws -> String? {
        try String.fetchOne(
            db, sql: "SELECT content_hash FROM \(table) WHERE \(idColumn) = ?", arguments: [id]
        )
    }

    // MARK: - Cycle

    @discardableResult
    static func upsert(_ db: GRDB.Database, cycle c: Cycle, inboxSeq: Int64) throws -> Bool {
        let hash = ContentHash.compute([
            c.scoreState.rawValue, c.updatedAt.timeIntervalSince1970,
            c.score?.strain, c.score?.kilojoule, c.score?.averageHeartRate, c.score?.maxHeartRate,
        ])
        let id = String(c.id)
        if try existingHash(db, table: "cycles", idColumn: "id", id: id) == hash { return false }

        try db.execute(
            sql: """
            INSERT INTO cycles
                (id, user_id, created_at, updated_at, start, end, timezone_offset, score_state,
                 strain, kilojoule, average_heart_rate, max_heart_rate, source, inbox_seq, content_hash)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                updated_at = excluded.updated_at, end = excluded.end, score_state = excluded.score_state,
                strain = excluded.strain, kilojoule = excluded.kilojoule,
                average_heart_rate = excluded.average_heart_rate, max_heart_rate = excluded.max_heart_rate,
                source = excluded.source, inbox_seq = excluded.inbox_seq, content_hash = excluded.content_hash
            """,
            arguments: [
                id, c.userId, Int64(c.createdAt.timeIntervalSince1970), Int64(c.updatedAt.timeIntervalSince1970),
                Int64(c.start.timeIntervalSince1970), c.end.map { Int64($0.timeIntervalSince1970) },
                c.timezoneOffset, c.scoreState.rawValue,
                c.score?.strain, c.score?.kilojoule, c.score?.averageHeartRate, c.score?.maxHeartRate,
                currentSource, inboxSeq, hash,
            ]
        )
        try markDirty(db, day: dayString(for: c.start), reason: "cycle")
        try trackPendingScore(db, resource: "cycle", recordId: id, scoreState: c.scoreState)
        return true
    }

    // MARK: - Recovery

    @discardableResult
    static func upsert(_ db: GRDB.Database, recovery r: Recovery, inboxSeq: Int64) throws -> Bool {
        let hash = ContentHash.compute([
            r.scoreState.rawValue, r.updatedAt.timeIntervalSince1970,
            r.score?.recoveryScore, r.score?.hrvRmssdMilli, r.score?.restingHeartRate,
            r.score?.spo2Percentage, r.score?.skinTempCelsius, r.score?.userCalibrating,
        ])
        let id = String(r.cycleId)
        if try existingHash(db, table: "recoveries", idColumn: "cycle_id", id: id) == hash { return false }

        try db.execute(
            sql: """
            INSERT INTO recoveries
                (cycle_id, sleep_id, user_id, created_at, updated_at, score_state, user_calibrating,
                 recovery_score, resting_heart_rate, hrv_rmssd_milli, spo2_percentage, skin_temp_celsius,
                 source, inbox_seq, content_hash)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(cycle_id) DO UPDATE SET
                sleep_id = excluded.sleep_id, updated_at = excluded.updated_at, score_state = excluded.score_state,
                user_calibrating = excluded.user_calibrating, recovery_score = excluded.recovery_score,
                resting_heart_rate = excluded.resting_heart_rate, hrv_rmssd_milli = excluded.hrv_rmssd_milli,
                spo2_percentage = excluded.spo2_percentage, skin_temp_celsius = excluded.skin_temp_celsius,
                source = excluded.source, inbox_seq = excluded.inbox_seq, content_hash = excluded.content_hash
            """,
            arguments: [
                id, r.sleepId, r.userId, Int64(r.createdAt.timeIntervalSince1970), Int64(r.updatedAt.timeIntervalSince1970),
                r.scoreState.rawValue, r.score?.userCalibrating ?? false,
                r.score?.recoveryScore, r.score?.restingHeartRate, r.score?.hrvRmssdMilli,
                r.score?.spo2Percentage, r.score?.skinTempCelsius,
                currentSource, inboxSeq, hash,
            ]
        )
        try markDirty(db, day: dayString(for: r.createdAt), reason: "recovery")
        try trackPendingScore(db, resource: "recovery", recordId: id, scoreState: r.scoreState)
        return true
    }

    // MARK: - Sleep

    @discardableResult
    static func upsert(_ db: GRDB.Database, sleep s: Sleep, inboxSeq: Int64) throws -> Bool {
        let hash = ContentHash.compute([
            s.scoreState.rawValue, s.updatedAt.timeIntervalSince1970,
            s.score?.sleepPerformancePercentage, s.score?.sleepEfficiencyPercentage,
            s.score?.sleepConsistencyPercentage, s.score?.respiratoryRate,
            s.score?.stageSummary.totalLightSleepTimeMilli, s.score?.stageSummary.totalSlowWaveSleepTimeMilli,
            s.score?.stageSummary.totalRemSleepTimeMilli, s.score?.stageSummary.totalAwakeTimeMilli,
        ])
        if try existingHash(db, table: "sleeps", idColumn: "id", id: s.id) == hash { return false }

        try db.execute(
            sql: """
            INSERT INTO sleeps
                (id, activity_v1_id, user_id, created_at, updated_at, start, end, timezone_offset, nap,
                 score_state, respiratory_rate, sleep_performance_percentage, sleep_consistency_percentage,
                 sleep_efficiency_percentage, source, inbox_seq, content_hash)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                updated_at = excluded.updated_at, score_state = excluded.score_state,
                respiratory_rate = excluded.respiratory_rate,
                sleep_performance_percentage = excluded.sleep_performance_percentage,
                sleep_consistency_percentage = excluded.sleep_consistency_percentage,
                sleep_efficiency_percentage = excluded.sleep_efficiency_percentage,
                source = excluded.source, inbox_seq = excluded.inbox_seq, content_hash = excluded.content_hash
            """,
            arguments: [
                s.id, s.v1Id, s.userId, Int64(s.createdAt.timeIntervalSince1970), Int64(s.updatedAt.timeIntervalSince1970),
                Int64(s.start.timeIntervalSince1970), Int64(s.end.timeIntervalSince1970), s.timezoneOffset, s.nap,
                s.scoreState.rawValue, s.score?.respiratoryRate, s.score?.sleepPerformancePercentage,
                s.score?.sleepConsistencyPercentage, s.score?.sleepEfficiencyPercentage,
                currentSource, inboxSeq, hash,
            ]
        )

        if let stage = s.score?.stageSummary {
            try db.execute(
                sql: """
                INSERT INTO sleep_stage_summary
                    (sleep_id, total_in_bed_time_milli, total_awake_time_milli, total_no_data_time_milli,
                     total_light_sleep_time_milli, total_slow_wave_sleep_time_milli, total_rem_sleep_time_milli,
                     sleep_cycle_count, disturbance_count)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(sleep_id) DO UPDATE SET
                    total_in_bed_time_milli = excluded.total_in_bed_time_milli,
                    total_awake_time_milli = excluded.total_awake_time_milli,
                    total_no_data_time_milli = excluded.total_no_data_time_milli,
                    total_light_sleep_time_milli = excluded.total_light_sleep_time_milli,
                    total_slow_wave_sleep_time_milli = excluded.total_slow_wave_sleep_time_milli,
                    total_rem_sleep_time_milli = excluded.total_rem_sleep_time_milli,
                    sleep_cycle_count = excluded.sleep_cycle_count, disturbance_count = excluded.disturbance_count
                """,
                arguments: [
                    s.id, stage.totalInBedTimeMilli, stage.totalAwakeTimeMilli, stage.totalNoDataTimeMilli,
                    stage.totalLightSleepTimeMilli, stage.totalSlowWaveSleepTimeMilli, stage.totalRemSleepTimeMilli,
                    stage.sleepCycleCount, stage.disturbanceCount,
                ]
            )
        }

        if let need = s.score?.sleepNeeded {
            try db.execute(
                sql: """
                INSERT INTO sleep_need
                    (sleep_id, baseline_milli, need_from_sleep_debt_milli, need_from_recent_strain_milli, need_from_recent_nap_milli)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(sleep_id) DO UPDATE SET
                    baseline_milli = excluded.baseline_milli,
                    need_from_sleep_debt_milli = excluded.need_from_sleep_debt_milli,
                    need_from_recent_strain_milli = excluded.need_from_recent_strain_milli,
                    need_from_recent_nap_milli = excluded.need_from_recent_nap_milli
                """,
                arguments: [s.id, need.baselineMilli, need.needFromSleepDebtMilli, need.needFromRecentStrainMilli, need.needFromRecentNapMilli]
            )
        }

        try markDirty(db, day: dayString(for: s.start), reason: "sleep")
        try trackPendingScore(db, resource: "sleep", recordId: s.id, scoreState: s.scoreState)
        return true
    }

    // MARK: - Workout

    @discardableResult
    static func upsert(_ db: GRDB.Database, workout w: Workout, inboxSeq: Int64) throws -> Bool {
        let hash = ContentHash.compute([
            w.scoreState.rawValue, w.updatedAt.timeIntervalSince1970,
            w.score?.strain, w.score?.averageHeartRate, w.score?.maxHeartRate, w.score?.kilojoule,
        ])
        if try existingHash(db, table: "workouts", idColumn: "id", id: w.id) == hash { return false }

        try db.execute(
            sql: """
            INSERT INTO workouts
                (id, activity_v1_id, user_id, created_at, updated_at, start, end, timezone_offset, sport_name,
                 score_state, strain, average_heart_rate, max_heart_rate, kilojoule, percent_recorded,
                 distance_meter, altitude_gain_meter, altitude_change_meter, source, inbox_seq, content_hash)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                updated_at = excluded.updated_at, score_state = excluded.score_state,
                strain = excluded.strain, average_heart_rate = excluded.average_heart_rate,
                max_heart_rate = excluded.max_heart_rate, kilojoule = excluded.kilojoule,
                percent_recorded = excluded.percent_recorded, distance_meter = excluded.distance_meter,
                altitude_gain_meter = excluded.altitude_gain_meter, altitude_change_meter = excluded.altitude_change_meter,
                source = excluded.source, inbox_seq = excluded.inbox_seq, content_hash = excluded.content_hash
            """,
            arguments: [
                w.id, w.v1Id, w.userId, Int64(w.createdAt.timeIntervalSince1970), Int64(w.updatedAt.timeIntervalSince1970),
                Int64(w.start.timeIntervalSince1970), Int64(w.end.timeIntervalSince1970), w.timezoneOffset, w.sportName,
                w.scoreState.rawValue, w.score?.strain, w.score?.averageHeartRate, w.score?.maxHeartRate, w.score?.kilojoule,
                w.score?.percentRecorded, w.score?.distanceMeter, w.score?.altitudeGainMeter, w.score?.altitudeChangeMeter,
                currentSource, inboxSeq, hash,
            ]
        )

        if let zones = w.score?.zoneDurations {
            try db.execute(
                sql: """
                INSERT INTO workout_zone_durations
                    (workout_id, zone_zero_milli, zone_one_milli, zone_two_milli, zone_three_milli, zone_four_milli, zone_five_milli)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(workout_id) DO UPDATE SET
                    zone_zero_milli = excluded.zone_zero_milli, zone_one_milli = excluded.zone_one_milli,
                    zone_two_milli = excluded.zone_two_milli, zone_three_milli = excluded.zone_three_milli,
                    zone_four_milli = excluded.zone_four_milli, zone_five_milli = excluded.zone_five_milli
                """,
                arguments: [
                    w.id, zones.zoneZeroMilli, zones.zoneOneMilli, zones.zoneTwoMilli,
                    zones.zoneThreeMilli, zones.zoneFourMilli, zones.zoneFiveMilli,
                ]
            )
        }

        try markDirty(db, day: dayString(for: w.start), reason: "workout")
        try trackPendingScore(db, resource: "workout", recordId: w.id, scoreState: w.scoreState)
        return true
    }

    // MARK: - Profile / body measurement (no score_state, no dirty-day marking)

    static func upsert(_ db: GRDB.Database, profile p: Profile) throws {
        try db.execute(
            sql: """
            INSERT INTO profile (user_id, email, first_name, last_name, updated_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(user_id) DO UPDATE SET
                email = excluded.email, first_name = excluded.first_name,
                last_name = excluded.last_name, updated_at = excluded.updated_at
            """,
            arguments: [p.userId, p.email, p.firstName, p.lastName, Int64(Date().timeIntervalSince1970)]
        )
    }

    static func upsert(_ db: GRDB.Database, bodyMeasurement b: BodyMeasurement, userId: Int64) throws {
        try db.execute(
            sql: """
            INSERT INTO body_measurements (user_id, height_meter, weight_kilogram, max_heart_rate, updated_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(user_id) DO UPDATE SET
                height_meter = excluded.height_meter, weight_kilogram = excluded.weight_kilogram,
                max_heart_rate = excluded.max_heart_rate, updated_at = excluded.updated_at
            """,
            arguments: [userId, b.heightMeter, b.weightKilogram, b.maxHeartRate, Int64(Date().timeIntervalSince1970)]
        )
    }
}
