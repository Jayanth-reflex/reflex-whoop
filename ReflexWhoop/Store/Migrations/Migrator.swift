import GRDB

/// All schema changes go through this migrator, one named migration per version.
/// Never edit a migration that has shipped — add a new one. GRDB tracks which
/// migrations have run in `grdb_migrations` and applies only the new ones.
enum Migrator {
    static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        // `eraseDatabaseOnSchemaChange` is deliberately NOT set, in any build
        // configuration. It used to be set under `#if DEBUG`, which protected
        // nothing: a free Apple ID ships Debug builds to the device, so the
        // "development only" wipe was armed on the only install that has ever
        // existed. Collected history is irreplaceable — WHOOP's backfill needs
        // the subscription that may be the very thing that lapsed — so no code
        // path may destroy it to save a developer a reinstall. See
        // docs/ADR-001-data-sovereignty.md, S1.
        //
        // The cost is that editing an already-applied migration makes the
        // database fail to open instead of silently resetting. That is the
        // correct failure: don't edit shipped migrations, add new ones.

        migrator.registerMigration("v1_initial_schema") { db in
            try createInboxLayer(db)
            try createNormalizedLayer(db)
            try createTimeSeriesLayer(db)
            try createDerivedLayer(db)
            try createControlLayer(db)
        }

        // Never edit v1 above — this is the pattern going forward: add a new
        // migration, never touch a shipped one. `user_calibrating` is needed so
        // BaselineEngine can exclude calibrating days from baseline math (per the
        // design doc) without re-joining back to `recoveries` for every window.
        migrator.registerMigration("v2_daily_metrics_calibrating") { db in
            try db.alter(table: "daily_metrics") { t in
                t.add(column: "user_calibrating", .boolean).notNull().defaults(to: false)
            }
        }

        return migrator
    }

    // MARK: - Layer 1: Inbox (append-only, lossless, source-agnostic)

    private static func createInboxLayer(_ db: GRDB.Database) throws {
        try db.create(table: "ingest_inbox") { t in
            t.autoIncrementedPrimaryKey("seq")
            t.column("source", .text).notNull()          // 'api' | 'ble'
            t.column("kind", .text).notNull()             // endpoint path, or BLE packet type
            t.column("received_at", .integer).notNull()   // unix seconds
            t.column("payload", .blob).notNull()           // API: JSON bytes. BLE: raw frame bytes.
            t.column("codec", .text).notNull().defaults(to: "raw") // 'raw' | 'zlib'
            t.column("decoded_at", .integer)               // NULL until normalizer has processed it
            t.column("decoder_version", .integer)
        }
        try db.create(index: "idx_inbox_undecoded", on: "ingest_inbox", columns: ["decoded_at"])
        try db.create(index: "idx_inbox_source_kind", on: "ingest_inbox", columns: ["source", "kind"])
    }

    // MARK: - Layer 2: Normalized records (API)

    private static func createNormalizedLayer(_ db: GRDB.Database) throws {
        try db.create(table: "cycles") { t in
            t.primaryKey("id", .text)                      // WHOOP cycle id (v2: integer serialized as text for uniformity)
            t.column("user_id", .integer)
            t.column("created_at", .integer)
            t.column("updated_at", .integer)
            t.column("start", .integer).notNull()
            t.column("end", .integer)                       // NULL while cycle is ongoing
            t.column("timezone_offset", .text)
            t.column("score_state", .text).notNull()
            t.column("strain", .double)
            t.column("kilojoule", .double)
            t.column("average_heart_rate", .integer)
            t.column("max_heart_rate", .integer)
            t.column("source", .text).notNull()
            t.column("inbox_seq", .integer)
            t.column("content_hash", .text)
        }
        try db.create(index: "idx_cycles_start", on: "cycles", columns: ["start"])

        try db.create(table: "recoveries") { t in
            t.primaryKey("cycle_id", .text)
            t.column("sleep_id", .text)
            t.column("user_id", .integer)
            t.column("created_at", .integer)
            t.column("updated_at", .integer)
            t.column("score_state", .text).notNull()
            t.column("user_calibrating", .boolean).notNull().defaults(to: false)
            t.column("recovery_score", .double)
            t.column("resting_heart_rate", .double)
            t.column("hrv_rmssd_milli", .double)
            t.column("spo2_percentage", .double)
            t.column("skin_temp_celsius", .double)
            t.column("source", .text).notNull()
            t.column("inbox_seq", .integer)
            t.column("content_hash", .text)
        }

        try db.create(table: "sleeps") { t in
            t.primaryKey("id", .text)                      // v2 UUID
            t.column("activity_v1_id", .integer)
            t.column("user_id", .integer)
            t.column("cycle_id", .text)
            t.column("created_at", .integer)
            t.column("updated_at", .integer)
            t.column("start", .integer).notNull()
            t.column("end", .integer).notNull()
            t.column("timezone_offset", .text)
            t.column("nap", .boolean).notNull().defaults(to: false)
            t.column("score_state", .text).notNull()
            t.column("respiratory_rate", .double)
            t.column("sleep_performance_percentage", .double)
            t.column("sleep_consistency_percentage", .double)
            t.column("sleep_efficiency_percentage", .double)
            t.column("source", .text).notNull()
            t.column("inbox_seq", .integer)
            t.column("content_hash", .text)
        }
        try db.create(index: "idx_sleeps_start", on: "sleeps", columns: ["start"])
        try db.create(index: "idx_sleeps_end", on: "sleeps", columns: ["end"])

        try db.create(table: "sleep_stage_summary") { t in
            t.primaryKey("sleep_id", .text).references("sleeps", onDelete: .cascade)
            t.column("total_in_bed_time_milli", .integer)
            t.column("total_awake_time_milli", .integer)
            t.column("total_no_data_time_milli", .integer)
            t.column("total_light_sleep_time_milli", .integer)
            t.column("total_slow_wave_sleep_time_milli", .integer)
            t.column("total_rem_sleep_time_milli", .integer)
            t.column("sleep_cycle_count", .integer)
            t.column("disturbance_count", .integer)
        }

        try db.create(table: "sleep_need") { t in
            t.primaryKey("sleep_id", .text).references("sleeps", onDelete: .cascade)
            t.column("baseline_milli", .integer)
            t.column("need_from_sleep_debt_milli", .integer)
            t.column("need_from_recent_strain_milli", .integer)
            t.column("need_from_recent_nap_milli", .integer)
        }

        try db.create(table: "workouts") { t in
            t.primaryKey("id", .text)                      // v2 UUID
            t.column("activity_v1_id", .integer)
            t.column("user_id", .integer)
            t.column("created_at", .integer)
            t.column("updated_at", .integer)
            t.column("start", .integer).notNull()
            t.column("end", .integer).notNull()
            t.column("timezone_offset", .text)
            t.column("sport_name", .text)
            t.column("score_state", .text).notNull()
            t.column("strain", .double)
            t.column("average_heart_rate", .integer)
            t.column("max_heart_rate", .integer)
            t.column("kilojoule", .double)
            t.column("percent_recorded", .double)
            t.column("distance_meter", .double)
            t.column("altitude_gain_meter", .double)
            t.column("altitude_change_meter", .double)
            t.column("source", .text).notNull()
            t.column("inbox_seq", .integer)
            t.column("content_hash", .text)
        }
        try db.create(index: "idx_workouts_start", on: "workouts", columns: ["start"])
        try db.create(index: "idx_workouts_sport", on: "workouts", columns: ["sport_name"])

        try db.create(table: "workout_zone_durations") { t in
            t.primaryKey("workout_id", .text).references("workouts", onDelete: .cascade)
            t.column("zone_zero_milli", .integer)
            t.column("zone_one_milli", .integer)
            t.column("zone_two_milli", .integer)
            t.column("zone_three_milli", .integer)
            t.column("zone_four_milli", .integer)
            t.column("zone_five_milli", .integer)
        }

        try db.create(table: "body_measurements") { t in
            t.primaryKey("user_id", .integer)
            t.column("height_meter", .double)
            t.column("weight_kilogram", .double)
            t.column("max_heart_rate", .integer)
            t.column("updated_at", .integer)
        }

        try db.create(table: "profile") { t in
            t.primaryKey("user_id", .integer)
            t.column("email", .text)
            t.column("first_name", .text)
            t.column("last_name", .text)
            t.column("updated_at", .integer)
        }
    }

    // MARK: - Layer 3: Time series (BLE) — columnar chunks + sessions

    private static func createTimeSeriesLayer(_ db: GRDB.Database) throws {
        try db.create(table: "ble_sessions") { t in
            t.primaryKey("id", .text)                      // UUID generated at session start
            t.column("started_at", .integer).notNull()
            t.column("ended_at", .integer)
            t.column("mode", .text).notNull()               // e.g. 'hr_rr' | 'hr_rr_accel' | 'all'
            t.column("band_firmware", .text)
            t.column("battery_start_pct", .integer)
            t.column("battery_end_pct", .integer)
            t.column("channels_json", .text)                // JSON array of channel names captured
            t.column("sample_count", .integer).notNull().defaults(to: 0)
            t.column("dropped_count", .integer).notNull().defaults(to: 0)
            t.column("byte_count", .integer).notNull().defaults(to: 0)
            t.column("ended_reason", .text)                 // 'user_stopped' | 'app_suspended' | 'ble_disconnected' | ...
        }

        try db.create(table: "ts_chunk") { t in
            t.column("channel", .text).notNull()
            t.column("session_id", .text).notNull().references("ble_sessions", onDelete: .cascade)
            t.column("bucket_start", .integer).notNull()    // epoch seconds, 1-hour buckets
            t.column("sample_count", .integer).notNull()
            t.column("nominal_hz", .double)
            t.column("first_ts", .integer).notNull()
            t.column("last_ts", .integer).notNull()
            t.column("encoding", .text).notNull()            // 'delta_zigzag_varint' | 'raw_u16' | 'raw_f32'
            t.column("codec", .text).notNull()               // 'lzfse' | 'zlib' | 'none'
            t.column("min_val", .double)
            t.column("max_val", .double)
            t.column("mean_val", .double)
            t.column("blob", .blob).notNull()
            t.primaryKey(["channel", "session_id", "bucket_start"])
        }
        try db.create(index: "idx_ts_chunk_bucket", on: "ts_chunk", columns: ["channel", "bucket_start"])

        try db.create(table: "ts_rollup_minute") { t in
            t.column("channel", .text).notNull()
            t.column("session_id", .text).notNull().references("ble_sessions", onDelete: .cascade)
            t.column("minute_start", .integer).notNull()     // epoch seconds, floored to the minute
            t.column("min_val", .double)
            t.column("max_val", .double)
            t.column("mean_val", .double)
            t.column("sample_count", .integer).notNull()
            t.primaryKey(["channel", "session_id", "minute_start"])
        }
    }

    // MARK: - Layer 4: Derived (recomputable, versioned)

    private static func createDerivedLayer(_ db: GRDB.Database) throws {
        try db.create(table: "daily_metrics") { t in
            t.primaryKey("day", .text)                      // ISO 8601 date, e.g. '2026-09-06'
            t.column("recovery_score", .double)
            t.column("hrv_rmssd_milli", .double)
            t.column("resting_heart_rate", .double)
            t.column("respiratory_rate", .double)
            t.column("skin_temp_celsius", .double)
            t.column("spo2_percentage", .double)
            t.column("day_strain", .double)
            t.column("sleep_performance_percentage", .double)
            t.column("sleep_debt_milli", .integer)
            t.column("readiness_score", .double)             // our own composite, not WHOOP's
            t.column("algo_version", .integer).notNull()
            t.column("confidence", .text)                    // 'strong' | 'moderate' | 'weak' | 'insufficient'
            t.column("computed_at", .integer).notNull()
        }

        try db.create(table: "baselines") { t in
            t.column("metric", .text).notNull()
            t.column("day", .text).notNull()
            t.column("window_days", .integer).notNull()      // 30 | 60
            t.column("mean_val", .double)
            t.column("stddev_val", .double)
            t.column("z_score", .double)
            t.column("excluded_calibrating", .boolean).notNull().defaults(to: false)
            t.column("algo_version", .integer).notNull()
            t.column("computed_at", .integer).notNull()
            t.primaryKey(["metric", "day", "window_days"])
        }

        try db.create(table: "correlations") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("predictor", .text).notNull()
            t.column("outcome", .text).notNull().defaults(to: "next_day_recovery")
            t.column("lag_days", .integer).notNull().defaults(to: 1)
            t.column("rho", .double).notNull()
            t.column("n", .integer).notNull()
            t.column("p_value", .double)
            t.column("p_value_bh_corrected", .double)
            t.column("strength", .text)                      // 'strong' | 'moderate' | 'weak' | 'insufficient'
            t.column("algo_version", .integer).notNull()
            t.column("computed_at", .integer).notNull()
        }

        try db.create(table: "anomalies") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("day", .text).notNull()
            t.column("kind", .text).notNull()                // 'illness_flag' | 'single_metric_excursion'
            t.column("metric", .text)
            t.column("z_score", .double)
            t.column("detail_json", .text)
            t.column("algo_version", .integer).notNull()
            t.column("computed_at", .integer).notNull()
        }
        try db.create(index: "idx_anomalies_day", on: "anomalies", columns: ["day"])

        try db.create(table: "session_metrics") { t in
            t.primaryKey("session_id", .text).references("ble_sessions", onDelete: .cascade)
            t.column("rmssd_milli", .double)
            t.column("sdnn_milli", .double)
            t.column("pnn50_pct", .double)
            t.column("dfa_alpha1", .double)
            t.column("rr_artifact_rejection_pct", .double)
            t.column("respiratory_rate", .double)
            t.column("signal_quality", .double)
            t.column("algo_version", .integer).notNull()
            t.column("computed_at", .integer).notNull()
        }
    }

    // MARK: - Layer 5: Control

    private static func createControlLayer(_ db: GRDB.Database) throws {
        try db.create(table: "sync_state") { t in
            t.primaryKey("resource", .text)                  // 'cycle' | 'recovery' | 'sleep' | 'workout' | 'profile' | 'body_measurement'
            t.column("last_synced_at", .integer)
            t.column("last_cursor", .text)                   // next_token, if a page was interrupted
            t.column("backfill_complete", .boolean).notNull().defaults(to: false)
        }

        try db.create(table: "pending_scores") { t in
            t.column("resource", .text).notNull()
            t.column("record_id", .text).notNull()
            t.column("first_seen_at", .integer).notNull()
            t.column("attempts", .integer).notNull().defaults(to: 0)
            t.primaryKey(["resource", "record_id"])
        }

        try db.create(table: "sync_log") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("started_at", .integer).notNull()
            t.column("finished_at", .integer)
            t.column("trigger", .text).notNull()             // 'foreground' | 'background' | 'manual' | 'backfill'
            t.column("resources_json", .text)
            t.column("requests_made", .integer).notNull().defaults(to: 0)
            t.column("records_upserted", .integer).notNull().defaults(to: 0)
            t.column("error", .text)
        }

        try db.create(table: "dirty_days") { t in
            t.column("day", .text).notNull()
            t.column("reason", .text).notNull()
            t.column("marked_at", .integer).notNull()
            t.primaryKey(["day", "reason"])
        }

        try db.create(table: "schema_meta") { t in
            t.primaryKey("key", .text)
            t.column("value", .text)
        }
    }
}
