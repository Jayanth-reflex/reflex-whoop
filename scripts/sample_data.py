"""Print SQL that fills a ReflexWhoop database with synthetic sample data.

For the documentation screenshots, and for looking at a screen without putting
real data on a simulator. Nothing here is a measurement of anybody: every series
is generated from a fixed seed, so the screenshots are reproducible. Derived rows
(baselines, anomalies, correlations) follow the same rules the app's engines use,
so the screens stay self-consistent.

    xcrun simctl install booted /path/to/ReflexWhoop.app
    xcrun simctl launch booted com.reflexwhoop.app      # creates the database
    xcrun simctl terminate booted com.reflexwhoop.app
    DB="$(xcrun simctl get_app_container booted com.reflexwhoop.app data)"
    python3 scripts/sample_data.py | sqlite3 "$DB/Documents/reflexwhoop.sqlite"

Nights are written at 22:45 in UTC+5:30, the timezone the screenshots were taken
in; change `BEDTIME_UTC_HOUR` for another one.
"""
import datetime as dt
import math
import random
import sys

DAYS = 120
SEED = 7
random.seed(SEED)

LATEST_DAY = dt.date(2026, 9, 15)  # the newest day key; its night ends on the 16th
BEDTIME_UTC_HOUR, BEDTIME_UTC_MINUTE = 17, 15  # 22:45 in UTC+5:30
today = LATEST_DAY
days = [today - dt.timedelta(days=i) for i in range(DAYS - 1, -1, -1)]


def wave(i, period, amp):
    return amp * math.sin(2 * math.pi * i / period)


# A day's strain and sleep come first; the next morning's readings respond to
# them, so the correlations the app computes point the way a body does.
rows = {}
previous_strain, previous_sleep = 11.0, 7.2
for i, day in enumerate(days):
    trend = i / DAYS  # gentle improvement across the window
    strain = max(3.0, min(19.5, 11 + wave(i, 9, 3.2) + random.gauss(0, 1.8)))
    sleep_hours = max(4.5, min(9.3, 7.2 + wave(i, 11, 0.6) + random.gauss(0, 0.55)))
    load = previous_strain - 11.0
    debt = previous_sleep - 7.2
    hrv = 64 + 8 * trend - 0.9 * load + 2.2 * debt + wave(i, 28, 3) + random.gauss(0, 6)
    rhr = 53 - 1.5 * trend + 0.3 * load - 0.5 * debt + random.gauss(0, 1.4)
    resp = 14.6 + 0.1 * load + wave(i, 11, 0.3) + random.gauss(0, 0.25)
    skin = 33.6 + wave(i, 9, 0.12) + random.gauss(0, 0.1)
    spo2 = 96.6 + wave(i, 5, 0.5) + random.gauss(0, 0.35)
    rows[day] = dict(hrv=hrv, rhr=rhr, resp=resp, skin=skin, spo2=spo2,
                     strain=strain, sleep_hours=sleep_hours)
    previous_strain, previous_sleep = strain, sleep_hours

# One night where several signals move away from normal together, so the illness
# flag and the unusual-days list have something real to show.
sick = days[-8]
rows[sick].update(hrv=rows[sick]["hrv"] - 15, rhr=rows[sick]["rhr"] + 3.4,
                  resp=rows[sick]["resp"] + 0.9, skin=rows[sick]["skin"] + 0.32,
                  strain=5.4, sleep_hours=6.3)
rows[days[-7]].update(hrv=rows[days[-7]]["hrv"] - 8, rhr=rows[days[-7]]["rhr"] + 1.8,
                      strain=6.4)

for day, r in rows.items():
    i = days.index(day)
    # Recovery tracks HRV up and resting heart rate down, as WHOOP's does.
    r["recovery"] = max(12, min(96, 0.82 * r["hrv"] - 2.2 * (r["rhr"] - 53) + 14))
    r["sleep_perf"] = max(45, min(100, 100 * r["sleep_hours"] / 8.2))


def epoch(day, hour, minute=0):
    return int(dt.datetime(day.year, day.month, day.day, hour, minute,
                           tzinfo=dt.timezone.utc).timestamp())


def sql_str(value):
    if value is None:
        return "NULL"
    if isinstance(value, str):
        return "'" + value.replace("'", "''") + "'"
    if isinstance(value, float):
        return f"{value:.4f}"
    return str(value)


def insert(table, **values):
    cols = ", ".join(values)
    vals = ", ".join(sql_str(v) for v in values.values())
    out.append(f"INSERT OR REPLACE INTO {table} ({cols}) VALUES ({vals});")


out = ["PRAGMA foreign_keys = OFF;", "BEGIN;"]
for table in ["cycles", "recoveries", "sleeps", "sleep_stage_summary", "sleep_need",
              "workouts", "workout_zone_durations", "daily_metrics", "baselines",
              "anomalies", "correlations", "profile", "body_measurements",
              "ble_sessions", "ts_rollup_minute", "session_metrics", "sync_state",
              "sync_log", "dirty_days"]:
    out.append(f"DELETE FROM {table};")

USER = 1001
insert("profile", user_id=USER, email="sample@example.com", first_name="Sample",
       last_name="Data", updated_at=epoch(today, 8))
insert("body_measurements", user_id=USER, height_meter=1.78, weight_kilogram=72.5,
       max_heart_rate=190, updated_at=epoch(today, 8))

now = epoch(today, 9)
for i, day in enumerate(days):
    r = rows[day]
    key = day.isoformat()
    is_today = day == today
    # 22:45 in the simulator's timezone (UTC+5:30), so the night's sleep ends the
    # next local morning — the case DayDates exists for.
    sleep_start = epoch(day, BEDTIME_UTC_HOUR, BEDTIME_UTC_MINUTE)
    sleep_end = sleep_start + int(r["sleep_hours"] * 3600)
    cycle_id = f"s{i:04d}"
    sleep_id = f"11111111-0000-4000-8000-{i:012d}"

    insert("cycles", id=cycle_id, user_id=USER, created_at=sleep_start,
           updated_at=sleep_end, start=sleep_start,
           end=None if is_today else sleep_start + 86_000,
           timezone_offset="+00:00", score_state="SCORED", strain=r["strain"],
           kilojoule=8200 + 300 * i % 2000, average_heart_rate=int(72 + r["strain"]),
           max_heart_rate=int(140 + r["strain"] * 2), source="api")
    insert("recoveries", cycle_id=cycle_id, sleep_id=sleep_id, user_id=USER,
           created_at=sleep_end, updated_at=sleep_end, score_state="SCORED",
           user_calibrating=0, recovery_score=r["recovery"],
           resting_heart_rate=r["rhr"], hrv_rmssd_milli=r["hrv"],
           spo2_percentage=r["spo2"], skin_temp_celsius=r["skin"], source="api")
    insert("sleeps", id=sleep_id, activity_v1_id=100000 + i, user_id=USER,
           cycle_id=cycle_id, created_at=sleep_end, updated_at=sleep_end,
           start=sleep_start, end=sleep_end, timezone_offset="+00:00", nap=0,
           score_state="SCORED", respiratory_rate=r["resp"],
           sleep_performance_percentage=r["sleep_perf"],
           sleep_consistency_percentage=68 + (i % 17),
           sleep_efficiency_percentage=88 + (i % 8), source="api")

    total = int(r["sleep_hours"] * 3_600_000)
    awake = int(total * 0.07)
    rem = int(total * 0.22)
    deep = int(total * 0.19)
    insert("sleep_stage_summary", sleep_id=sleep_id, total_in_bed_time_milli=total,
           total_awake_time_milli=awake, total_no_data_time_milli=0,
           total_light_sleep_time_milli=total - awake - rem - deep,
           total_slow_wave_sleep_time_milli=deep, total_rem_sleep_time_milli=rem,
           sleep_cycle_count=4 + (i % 3), disturbance_count=3 + (i % 5))
    insert("sleep_need", sleep_id=sleep_id, baseline_milli=28_800_000,
           need_from_sleep_debt_milli=7_668_000,
           need_from_recent_strain_milli=600_000 + (i % 7) * 120_000,
           need_from_recent_nap_milli=0)

    insert("daily_metrics", day=key, recovery_score=r["recovery"],
           hrv_rmssd_milli=r["hrv"], resting_heart_rate=r["rhr"],
           respiratory_rate=r["resp"], skin_temp_celsius=r["skin"],
           spo2_percentage=r["spo2"], day_strain=r["strain"],
           sleep_performance_percentage=r["sleep_perf"],
           sleep_debt_milli=7_668_000, readiness_score=None, algo_version=1,
           confidence="moderate", computed_at=now, user_calibrating=0)

    if i % 3 == 0 and not is_today:
        workout_id = f"22222222-0000-4000-8000-{i:012d}"
        start = epoch(day, 11, 30)
        duration = 2400 + (i % 5) * 600
        sport = ["Running", "Cycling", "Weightlifting", "Swimming"][i % 4]
        insert("workouts", id=workout_id, activity_v1_id=200000 + i, user_id=USER,
               created_at=start, updated_at=start + duration, start=start,
               end=start + duration, timezone_offset="+00:00", sport_name=sport,
               score_state="SCORED", strain=max(4.0, r["strain"] - 2),
               average_heart_rate=int(128 + (i % 9)), max_heart_rate=int(162 + (i % 11)),
               kilojoule=1600 + (i % 6) * 120, percent_recorded=100.0,
               distance_meter=6200 + (i % 5) * 800 if sport in ("Running", "Cycling") else None,
               altitude_gain_meter=None, altitude_change_meter=None, source="api")
        insert("workout_zone_durations", workout_id=workout_id,
               zone_zero_milli=120_000, zone_one_milli=300_000, zone_two_milli=900_000,
               zone_three_milli=700_000, zone_four_milli=300_000, zone_five_milli=60_000)

# --- Derived: baselines, exactly as BaselineEngine computes them ----------------
METRICS = {"recovery_score": "recovery", "hrv_rmssd_milli": "hrv",
           "resting_heart_rate": "rhr", "respiratory_rate": "resp",
           "skin_temp_celsius": "skin", "spo2_percentage": "spo2"}
MIN_SAMPLES = 5
z_by_day = {}
for metric, field in METRICS.items():
    for i, day in enumerate(days):
        for window in (30, 60):
            history = [rows[d][field] for d in days[max(0, i - window):i]]
            if len(history) < MIN_SAMPLES:
                continue
            mean = sum(history) / len(history)
            var = sum((v - mean) ** 2 for v in history) / (len(history) - 1)
            sd = math.sqrt(var)
            value = rows[day][field]
            z = (value - mean) / sd if sd > 0 else None
            insert("baselines", metric=metric, day=day.isoformat(), window_days=window,
                   mean_val=mean, stddev_val=sd, z_score=z, excluded_calibrating=0,
                   algo_version=1, computed_at=now)
            if window == 60 and z is not None:
                z_by_day.setdefault(day, {})[metric] = z

# --- Derived: anomalies, AnomalyEngine's two rules ------------------------------
ILLNESS = [("respiratory_rate", 1), ("skin_temp_celsius", 1),
           ("resting_heart_rate", 1), ("hrv_rmssd_milli", -1)]
anomaly_id = 0
for day, zs in z_by_day.items():
    triggered = [m for m, direction in ILLNESS
                 if m in zs and zs[m] * direction >= 1.5]
    if len(triggered) >= 3:
        detail = ('{"triggeredSignals":[' + ",".join(f'"{m}"' for m in triggered) + '],"zScores":{'
                  + ",".join(f'"{m}":{zs[m]:.3f}' for m in triggered) + "}}")
        anomaly_id += 1
        insert("anomalies", id=anomaly_id, day=day.isoformat(), kind="illness_flag",
               metric=None, z_score=None, detail_json=detail, algo_version=1,
               computed_at=now)
    for metric, z in zs.items():
        if abs(z) >= 2.0:
            anomaly_id += 1
            insert("anomalies", id=anomaly_id, day=day.isoformat(),
                   kind="single_metric_excursion", metric=metric, z_score=z,
                   detail_json=None, algo_version=1, computed_at=now)

# --- Derived: correlations, Spearman + Benjamini-Hochberg ----------------------
def ranks(xs):
    order = sorted(range(len(xs)), key=lambda i: xs[i])
    out_ranks = [0.0] * len(xs)
    i = 0
    while i < len(order):
        j = i
        while j + 1 < len(order) and xs[order[j + 1]] == xs[order[i]]:
            j += 1
        average = (i + j) / 2.0 + 1.0
        for k in range(i, j + 1):
            out_ranks[order[k]] = average
        i = j + 1
    return out_ranks


def pearson(xs, ys):
    n = len(xs)
    mx, my = sum(xs) / n, sum(ys) / n
    num = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    den = math.sqrt(sum((x - mx) ** 2 for x in xs) * sum((y - my) ** 2 for y in ys))
    return num / den if den else 0.0


def two_sided_p(rho, n):
    if n <= 2 or abs(rho) >= 1:
        return 0.0
    t = abs(rho) * math.sqrt((n - 2) / (1 - rho * rho))
    df = n - 2
    x = df / (df + t * t)
    # Regularized incomplete beta via continued fraction is overkill here; a
    # normal approximation is close enough for sample display values.
    zscore = t * (1 - 1 / (4 * df)) / math.sqrt(1 + t * t / (2 * df))
    return max(1e-6, math.erfc(zscore / math.sqrt(2))) if x else 0.0


PREDICTORS = {
    "prior_day_strain": lambda i: rows[days[i]]["strain"],
    "respiratory_rate": lambda i: rows[days[i]]["resp"],
    "sleep_duration_hours": lambda i: rows[days[i]]["sleep_hours"],
    "sleep_efficiency_pct": lambda i: 88 + (i % 8),
    "sleep_consistency_pct": lambda i: 68 + (i % 17),
    "rem_sleep_pct": lambda i: 22.0 + math.sin(i / 4) * 2,
    "slow_wave_sleep_pct": lambda i: 19.0 + math.cos(i / 5) * 2,
    "sleep_disturbance_count": lambda i: 3 + (i % 5),
}
results = []
for name, value_at in PREDICTORS.items():
    xs, ys = [], []
    for i in range(len(days) - 1):
        xs.append(value_at(i))
        ys.append(rows[days[i + 1]]["recovery"])
    rho = pearson(ranks(xs), ranks(ys))
    results.append((name, rho, len(xs), two_sided_p(rho, len(xs))))

ps = [r[3] for r in results]
order = sorted(range(len(ps)), key=lambda i: ps[i])
adjusted = [0.0] * len(ps)
running = 1.0
for rank in range(len(ps) - 1, -1, -1):
    i = order[rank]
    running = min(running, ps[i] * len(ps) / (rank + 1))
    adjusted[i] = min(running, 1.0)

for (name, rho, n, p), p_bh in zip(results, adjusted):
    strength = "insufficient" if n < 30 else (
        "strong" if abs(rho) >= 0.5 else "moderate" if abs(rho) >= 0.3 else "weak")
    insert("correlations", predictor=name, outcome="next_day_recovery", lag_days=1,
           rho=rho, n=n, p_value=p, p_value_bh_corrected=p_bh, strength=strength,
           algo_version=1, computed_at=now)

# --- A band recording, so the Band tab has a real chart ------------------------
session_id = "33333333-0000-4000-8000-000000000001"
session_start = epoch(today, 1, 10)
minutes = 42
insert("ble_sessions", id=session_id, started_at=session_start,
       ended_at=session_start + minutes * 60, mode="continuous",
       band_firmware="50.41.1.0", battery_start_pct=84, battery_end_pct=82,
       channels_json='["hr"]', sample_count=minutes * 60, dropped_count=0,
       byte_count=minutes * 60 * 24, ended_reason="user_stopped")
hr_values = []
for m in range(minutes):
    base = 58 + 18 * math.sin(m / 7.0) + (m / minutes) * 10
    mean = base + random.gauss(0, 1.5)
    hr_values.append(mean)
    insert("ts_rollup_minute", channel="hr", session_id=session_id,
           minute_start=session_start + m * 60, min_val=mean - 3, max_val=mean + 4,
           mean_val=mean, sample_count=60)
insert("session_metrics", session_id=session_id, rmssd_milli=None, sdnn_milli=None,
       pnn50_pct=None, dfa_alpha1=None, rr_artifact_rejection_pct=None,
       respiratory_rate=None, signal_quality=0.97, algo_version=1, computed_at=now,
       hr_sample_count=minutes * 60, hr_mean=sum(hr_values) / len(hr_values),
       hr_min=min(hr_values) - 3, hr_max=max(hr_values) + 4,
       decoded_frame_count=minutes * 60, unmapped_frame_count=64, corrupt_frame_count=0)

for resource in ["cycle", "recovery", "sleep", "workout", "profile", "body_measurement"]:
    insert("sync_state", resource=resource, last_synced_at=now - 1800,
           last_cursor=None, backfill_complete=1)

out.append("COMMIT;")
sys.stdout.write("\n".join(out) + "\n")
