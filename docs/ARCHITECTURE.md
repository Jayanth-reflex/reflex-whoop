# Architecture

How ReflexWhoop is put together, as built. Why particular choices were made is in
[`DECISIONS.md`](DECISIONS.md); the band's wire protocol and the Bluetooth safety
rails are in [`PROTOCOL-GEN5.md`](PROTOCOL-GEN5.md); the visual system is in
[`DESIGN-SYSTEM.md`](DESIGN-SYSTEM.md).

## Principles

1. **The archive is sacred.** No code path destroys collected history, in any build
   configuration. Migrations are append-only; an edited migration fails to open the
   database rather than resetting it ([ADR-001](ADR-001-data-sovereignty.md)).
2. **Inbox first, decode second.** Every byte from every source lands untouched in
   `ingest_inbox` before anything parses it. A decoder bug is never data loss: fix the
   decoder and replay.
3. **Never fabricate a value.** Missing input yields `NULL` and a reason, never zero,
   never an interpolation the UI can't tell from a measurement. Absent input yields
   "unavailable", not zero.
4. **Analysis reads a source-neutral layer.** WHOOP's API and the band are adapters.
   See [the source-neutral contract](#the-source-neutral-contract).
5. **Every source can be absent.** "WHOOP inactive" and "no band" are designed,
   displayed, tested states, not error paths.
6. **The band is read-only and live-stream only.** The app never reads the band's
   stored history and cannot change anything on it
   ([safety rails](PROTOCOL-GEN5.md#safety-rails)).

## Data flow

```
 SOURCES (adapters)            INBOX            NEUTRAL LAYER          ANALYSIS + UI
┌───────────────────┐                      ┌──────────────────┐   ┌──────────────────┐
│ WhoopClient       │   ┌──────────────┐   │ daily_metrics    │   │ BaselineEngine   │
│  (ApiSyncEngine)  │──▶│ ingest_inbox │──▶│  (one row/day)   │──▶│ AnomalyEngine    │
│                   │   │ append-only, │   │                  │   │ CorrelationEngine│
│ BandConnection    │──▶│ raw bytes    │──▶│ ts_chunk         │   │ ReadinessEngine  │
│  (SpikeRecorder)  │   └──────────────┘   │ ts_rollup_minute │   │                  │
└───────────────────┘   ApiNormalizer      │ session_metrics  │   │ SwiftUI screens  │
                        BleNormalizer      └──────────────────┘   │ Export → MCP     │
                                                                  └──────────────────┘
```

## Source A: WHOOP API v2

Base `https://api.prod.whoop.com/developer`, v2 only.

| Endpoint | What it gives |
|---|---|
| `GET /v2/cycle` | day strain, kilojoules, average/max HR, start/end, `timezone_offset` |
| `GET /v2/recovery` | recovery %, `hrv_rmssd_milli`, resting HR, SpO2 %, skin temperature °C, `user_calibrating` |
| `GET /v2/activity/sleep` | stage totals, sleep need breakdown, performance/consistency/efficiency %, respiratory rate, `nap` |
| `GET /v2/activity/workout` | sport, strain, average/max HR, kilojoules, distance, altitude, zone durations |
| `GET /v2/user/profile/basic` | name, email |
| `GET /v2/user/measurement/body` | height, weight, max HR |

**Auth** (`Auth/`): OAuth2 through `ASWebAuthenticationSession`, redirect
`reflexwhoop://oauth/callback`, a random `state` verified on return. The user enters
their own WHOOP developer app's client ID and secret in the app; they, the access
token and the refresh token live only in the Keychain. WHOOP rotates refresh tokens
on every use, so `TokenStore` persists the new pair atomically. Scopes are the six
`read:*` scopes plus `offline`, which is what makes WHOOP issue a refresh token.

**Client** (`Api/`): `RateLimiter` stays under 100 requests/minute and 10,000/day and
honours `X-RateLimit-Reset` on a 429. A 401 forces one token refresh and a retry.
HTTP 403 is recorded as `inactive` (a lapsed membership), distinct from transient
failures, via `sync_log.error_kind`.

**Sync** (`Sync/`): `ApiSyncEngine` runs three modes in one pass:

- **Backfill** walks each collection's full history by cursor, checkpointed per page,
  so killing the app mid-backfill loses at most one page.
- **Incremental** re-pulls a 7-day lookback, because WHOOP re-scores sleep and
  recovery retroactively. Writes are `INSERT … ON CONFLICT DO UPDATE`, and
  `RecordDAO`'s content hash makes an unchanged record a comparison, not a write.
- **Pending-score re-fetch** retries records WHOOP hadn't finished scoring
  (`score_state = PENDING_SCORE`).

`SyncPolicy` gives each resource a staleness budget (workouts 30 min, sleep and
recovery 1 h, cycles 4 h, profile and body 24 h), so opening the app fetches only
what is stale. Sync runs on foreground, on demand, and from a `BGAppRefreshTask`
(`com.reflexwhoop.sync.refresh`).

`SourceStatus` turns the sync log into a `SourceState`: `active`, `notConfigured`,
`unauthorized`, `inactive` or `unreachable`. When WHOOP can no longer contribute,
every screen keeps working from the archive and says what state the source is in.

## Source B: the band over Bluetooth

`BandConnection` connects to the WHOOP 5.0 band's custom `fd4b…` GATT service using
the bond the official WHOOP app already holds; no re-pairing. Every outgoing command
passes through `OpcodeAllowlist`, which only admits live-stream and read-only opcodes.
Inbound frames are appended to the inbox as they arrive. The protocol, what is
decoded, and the rails are in [`PROTOCOL-GEN5.md`](PROTOCOL-GEN5.md).

**Keep recording** (`CollectionSettings`, off by default) is the only way to record.
On, `AppContainer` holds one app-lifetime `SpikeRecorder` that reconnects by itself,
uses the `bluetooth-central` background mode and CoreBluetooth state restoration, and
writes an end-time watermark so a session killed mid-recording still has a real end.
iOS can still suspend or terminate a background app, so recordings can have gaps.

`BleNormalizer` turns a session's inbox rows into samples: reassemble, decode
confirmed fields only (today: heart rate), write them through `ChunkStore`, and record
`session_metrics` with decode coverage (`decoded` / `unmapped` / `corrupt` frames and
`signal_quality`). A collapsing decode ratio while frames keep arriving is the signal
that a firmware update moved something. **Rebuild heart-rate history** in Archive
replays every session from the inbox after a decoder change.

## Storage

SQLite through GRDB (`DatabasePool`, WAL) at `Documents/reflexwhoop.sqlite`, with
`synchronous=NORMAL`, `mmap_size=256MB` and `auto_vacuum=INCREMENTAL`. Documents is
exposed in Files and Finder (`UIFileSharingEnabled`), which is also the export path.

| Layer | Tables | Notes |
|---|---|---|
| Inbox | `ingest_inbox` | Append-only. API JSON is zlib-compressed; BLE frames are stored raw. `decoded_at` and `decoder_version` track processing. |
| Normalized (API) | `cycles`, `recoveries`, `sleeps`, `sleep_stage_summary`, `sleep_need`, `workouts`, `workout_zone_durations`, `body_measurements`, `profile` | Every row keeps `score_state`, `timezone_offset`, `inbox_seq` and `content_hash`. |
| Time series (BLE) | `ble_sessions`, `ts_chunk`, `ts_rollup_minute` | One-hour chunks per channel and session. Samples are delta, zigzag and varint encoded (`ChunkCodec`), then compressed, whichever is smaller. Charts read the per-minute rollup and never decode chunks. |
| Derived | `daily_metrics`, `baselines`, `anomalies`, `correlations`, `session_metrics` | Recomputable. Each row carries `algo_version`. |
| Control | `sync_state`, `pending_scores`, `sync_log`, `dirty_days`, `schema_meta` | `schema_meta` records schema and decoder versions, so a snapshot is self-describing. |

## Analysis

Pure Swift in `Analysis/`, no SwiftUI. After a sync or a recording, `AnalysisEngine`
recomputes only the days in `dirty_days`, in one write transaction.

- **`DailyMetricsBuilder`** is the WHOOP adapter: one `daily_metrics` row per day from
  that day's cycle, recovery and main sleep.
- **`BaselineEngine`**: 30- and 60-day mean, SD and z-score for recovery, HRV, resting
  HR, respiratory rate, skin temperature and SpO2. The window is the days strictly
  before the day being scored, so an extreme value can't pull its own baseline toward
  itself. Days WHOOP marks as calibrating are excluded.
- **`AnomalyEngine`**: a single-metric excursion at |z| ≥ 2 on the 60-day baseline,
  and an illness flag when at least three of respiratory rate ↑, skin temperature ↑,
  resting HR ↑ and HRV ↓ pass 1.5 SD together. Every normal range the UI draws uses
  the same window and threshold, so a reading can't look normal on one screen and
  unusual on another.
- **`CorrelationEngine`**: lagged Spearman correlations of next-day recovery against
  prior-day strain, sleep duration, efficiency, consistency, REM %, slow-wave %,
  disturbances, respiratory rate and acute:chronic load. Benjamini–Hochberg corrects
  across the whole batch, and fewer than 30 days reports "insufficient". Correlations
  on one person's data are suggestive, not causal, and the UI never implies otherwise.
- **`ReadinessEngine`**: the app's own composite of HRV, resting HR, sleep debt and
  load, never WHOOP's recovery score. It is computed and exported but shown on no
  screen until its sleep-debt input is rebuilt
  ([DECISIONS](DECISIONS.md#readiness-hidden-until-sleep-debt-is-rebuilt)).

Days are keyed by the UTC date their cycle started (`RecordDAO.dayString`), which is
what every engine joins on. Screens show a day as the local morning its main sleep
ended (`DayDates`).

## The source-neutral contract

Anything left of the neutral layer may know what WHOOP is. Nothing right of it may.

- **`daily_metrics`**: physiological quantities with no vendor semantics.
  `recovery_score` and `day_strain` are WHOOP's own scores, carried because they're
  useful; anything that reads them must tolerate `NULL`, which a non-WHOOP source
  would leave.
- **`ts_chunk` / `ts_rollup_minute`**: keyed by a neutral channel name, `"hr"`, not a
  packet type (`BleNormalizer.Channel`). A second heart-rate source writes `"hr"` too.
- **`session_metrics`**: `hr_mean`, `rmssd_milli`, `signal_quality`; nothing implies
  a WHOOP band produced them.

**Known exceptions.** `CorrelationEngine` and the detail read models in
`AnalysisQueries` read sleep-stage and sleep-need detail straight from the WHOOP
tables, because `daily_metrics` doesn't carry it. They are read-only extras, not the
baseline/anomaly path, and widening the neutral layer is better decided when a second
source shows what shape it needs. **New code must not add a read of a WHOOP-shaped
table from `Analysis/`.** Put the value in the neutral layer first.

**Adding a source:**

1. An adapter that lands raw bytes in `ingest_inbox`.
2. A normalizer that writes `daily_metrics` rows and/or `ChunkStore` samples, only for
   fields it can actually decode.
3. A `SourceState` for it, so it can be absent gracefully.
4. No change in `Analysis/` or `UI/`. If one is needed, the boundary leaked; fix the
   boundary.

## App and UI

`App/AppContainer` is the composition root: database, auth, sync engine, recorder.
Four tabs: **Today · Trends · Band · Archive**, plus a first-run flow shown only to an
install with no data and no WHOOP account.

Views hold no SQL and no arithmetic. Screen-shaped read models in `Analysis/`
(`TodaySnapshot`, `MetricHistory`, `RecordingQueries`, `UnusualDays`,
`PatternsSummary`, …) return value types; views load them in `.task`, and Today
observes the database with `ValueObservation` so it updates when a sync lands.
Screens and components are described in [`DESIGN-SYSTEM.md`](DESIGN-SYSTEM.md).

## Export and MCP

**Export a copy** writes `Documents/exports/<local timestamp>/`:

- a CSV per normalized and derived table;
- `reflexwhoop.sqlite`, a `VACUUM INTO` snapshot, safe to take from a live WAL database;
- `raw_api.jsonl` and `ble_sessions/<id>.bin`, the untouched payloads;
- `manifest.json`: export time, applied migrations, algorithm versions, row and byte
  counts, date ranges.

A share sheet sends it anywhere; the folder is also visible in Files and Finder.
[`mcp-server/`](../mcp-server/README.md) opens that snapshot read-only on a Mac so
Claude can query it, and converts CSVs to Parquet.

## Platform constraints

A free Apple ID (Personal Team) grants no entitlement-backed capability: no iCloud,
App Groups, push, HealthKit or widgets. Background App Refresh, `bluetooth-central`,
the Keychain and file sharing need none. A build signed this way expires after 7 days;
reinstalling loses nothing, because sync is watermark-driven and backfills the gap.

## Limits

- **Not in the API or on the band:** WHOOP Age, Healthspan, hormonal insights, blood
  pressure, journal, Strain Coach, stress monitor.
- **The band holds signal, not scores.** Recovery, strain and sleep stages are computed
  in WHOOP's cloud. Bluetooth complements the API; it doesn't replace it.
- **One decoded channel.** Heart rate is confirmed; beat-to-beat RR, optical and IMU
  records are not, so HRV from the band (rMSSD, SDNN, pNN50, DFA-α1) and the app's own
  respiratory rate stay `NULL`.
- **The protocol is reverse-engineered.** A firmware update can break decoding. The
  inbox keeps the bytes; it doesn't keep the decoder working.
- **The WHOOP client secret lives on the device**, in the Keychain, entered by the
  user. Never in the binary, never in git.
