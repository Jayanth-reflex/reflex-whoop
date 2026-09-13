# ReflexWhoop — dual-source WHOOP 5.0 collector, analyzer, and local store (iOS)

## Context

You wear a WHOOP 5.0 on the Peak tier. The official app shows you scores and hides
everything else: no raw export, no history you own, no baselines you control, no
correlation analysis, and nothing at a resolution finer than one number per night.

This project builds a **personal iPhone app** that collects your data from **two
independent sources**, stores it losslessly on-device, computes the analysis WHOOP won't
give you, and hands a snapshot to your Mac so Claude can query your own physiology.

Personal use, single member. No App Store, no approval — WHOOP permits 10 members in
development mode without review.

**Target directory:** `/Users/jayanth/Desktop/resume/projects/reflex-whoop` (empty).

### Decisions locked in

| | |
|---|---|
| Runtime | Native SwiftUI iPhone app, all data on-device |
| Install | Xcode + cable, **free Apple ID** (7-day cert) |
| Source A | WHOOP Cloud API v2, polling (no webhooks, no server) |
| Source B | Direct BLE to the band — **live-stream only, flash drain never implemented** |
| Retention | Keep everything forever |
| Analysis | Trends, baselines, correlations, plus BLE-only metrics the API can't produce |
| Export | CSV + SQLite snapshot; Parquet converted on the Mac |
| Claude | MCP server on the Mac, read-only |
| UI | WHOOP-like, dark, insight-first |

---

## The two sources, and why both

They are complementary, not redundant. Neither alone is enough.

| | **Cloud API v2** | **BLE direct (live)** |
|---|---|---|
| Coverage | 24/7 automatic, nothing to remember | only while a session is running |
| Resolution | ~4 records per day | 1 Hz historical-grade / ~100 Hz live |
| Heart rate | avg + max per cycle | continuous, beat by beat |
| **RR intervals** | ✗ — one nightly rMSSD | ✓ **every beat** |
| Raw PPG waveform | ✗ | ✓ green + red/IR ADC |
| Accelerometer | ✗ | ✓ tri-axial f32 |
| Recovery / Strain / Sleep stages | ✓ WHOOP's own scores | ✗ computed in their cloud |
| Stability | documented, versioned, stable | reverse-engineered, breaks on firmware |

**Division of labor:** the API is the spine — continuous daily history and WHOOP's official
scores. BLE is the microscope — you start a session (a night, a workout, a five-minute
seated HRV reading) and get the underlying signal that no WHOOP surface exposes.

The RR intervals are the prize. With every beat-to-beat interval you can compute SDNN,
pNN50, DFA-α1 (aerobic threshold estimation), per-hour and intra-workout HRV, and HRV
recovery slope after intervals. WHOOP gives you one rMSSD number per night and calls it
done.

### What is off the table

**Cloud API does not expose:** WHOOP Age / Healthspan, Hormonal Insights, Health Monitor
trend views, Blood Pressure (MG only), Journal entries, Strain Coach targets, Stress
Monitor. Peak-tier features are app-only. Do not promise them in the UI.

**BLE does not expose:** recovery score, strain score, sleep stages — all computed in
WHOOP's cloud from the raw signal, not on the band.

We can derive our *own* readiness score from HRV + RHR + sleep + load. It must be labeled
as ours everywhere it appears.

---

## Source A — Cloud API v2

Base `https://api.prod.whoop.com/developer`. v2 only; v1 and v1 webhooks are removed.

| Endpoint | Payload highlights |
|---|---|
| `GET /v2/cycle` | day strain, kilojoule, avg/max HR, start/end, `timezone_offset` |
| `GET /v2/recovery` | recovery %, `hrv_rmssd_milli`, resting HR, SpO2 %, skin temp °C, `user_calibrating` |
| `GET /v2/activity/sleep` | UUID, stage summary (light/SWS/REM/awake/no-data ms, cycle count, disturbances), sleep need breakdown (baseline / debt / recent strain / recent nap), performance %, consistency %, efficiency %, respiratory rate, `nap` |
| `GET /v2/activity/workout` | UUID, `sport_name`, strain, avg/max HR, kJ, `percent_recorded`, distance, altitude gain/change, `zone_durations` (zone_zero…zone_five ms) |
| `GET /v2/user/profile/basic` | name, email |
| `GET /v2/user/measurement/body` | height, weight, max HR |

**Mechanics that shape the design:**

- OAuth2 — auth `https://api.prod.whoop.com/oauth/oauth2/auth`, token `…/oauth2/token`.
- Scopes `read:profile read:body_measurement read:cycles read:recovery read:sleep read:workout offline`.
  Note WHOOP's inconsistent pluralization: `read:cycles` plural, `read:workout` singular.
- `offline` is mandatory or you never get a refresh token.
- **Refresh tokens rotate.** Using one invalidates the old access token *and* returns a new
  refresh token. A partial write loses the account. Persist atomically.
- Redirect URI must be pre-registered; custom scheme is allowed — `reflexwhoop://oauth/callback`.
- `state` required — 16 random bytes, verified on return.
- Rate limit **100 req/min, 10 000/day**; headers `X-RateLimit-Limit/-Remaining/-Reset`; 429 on breach.
- Pagination `start`, `end` (ISO 8601 `2022-01-01T00:00:00.000Z`), `limit`, `nextToken`;
  response carries `next_token`, empty means done. Confirm each endpoint's max `limit` from
  the reference at implementation time (collections cap low — assume 25).
- **`score_state` ∈ `SCORED | PENDING_SCORE | UNSCORABLE`.** Records arrive unscored and fill
  in later; sleeps get **retroactively re-scored**. Sync must re-fetch and upsert, never append.

---

## Source B — BLE direct to the band (WHOOP 5.0)

### Gen 5 protocol — confirmed differences from Gen 4

OpenStrap's `PROTOCOL.md` is explicitly **Gen 4 only** (`6108…` service). Your band is Gen 5
and differs:

| | Gen 4 | **Gen 5 (yours)** |
|---|---|---|
| Service UUID | `61080001-8d6d-82b8-614a-1c8cb0f8dcc6` | **`fd4b0001-cce1-4033-93ce-002d5875f58a`** |
| Envelope | `[0xAA][u16 len][CRC8(len)][inner padded /4][u32 CRC32]` | **`[0xAA][0x01][len][field][CRC-16/MODBUS][inner][CRC-32]`** |
| Length checksum | CRC-8, poly 0x07 | **CRC-16/MODBUS** |
| Writes | either | **write-with-response required — write-without-response is a no-op** |
| Extra characteristic | — | **`fd4b0007` notify, new in 5.0** |

Characteristics: `fd4b0002` write (commands), `fd4b0003` notify (command responses),
`fd4b0004` notify (events), `fd4b0005` notify (data, fragmented), `fd4b0007` notify (new).

Inner packet is unchanged: `[packet_type][seq][opcode / event_id / record_type][body…]`.
Packet types `0x23` command · `0x24` response · `0x28` realtime compact HR · `0x2B`
realtime raw (R10) · `0x2F` historical · `0x30` event · `0x31` sync marker · `0x33`/`0x34` IMU.

**Reassembly must be length-based, not `0xAA`-triggered** — sensor payloads contain `0xAA`
bytes constantly. This is the single most common way a decoder silently corrupts data.

**Bonding:** Gen 5 requires *authenticated* pairing, not just-works. You do not need to
re-pair — your phone already holds an OS-level bond from the official WHOOP app, and a
second app on the same phone inherits it. CoreBluetooth connects and subscribes to the
custom notify characteristics using that bond. The official app does not need to be closed.

### Safety rails — non-negotiable

You are on an active paid subscription. The flash read cursor is **shared and persists
across connections**; draining it could starve the official app and corrupt your real
recovery and strain scores.

**Therefore the app implements a compile-time opcode allowlist, enforced in one place and
covered by a unit test.** Permitted:

| Opcode | Command | Why safe |
|---|---|---|
| `0x23` | `GET_HELLO_HARVARD` | read-only identity/battery/wrist |
| `0x1A` | `GET_BATTERY_LEVEL` | read-only (`0x180F` is buggy, returns constant 100%) |
| `0x22` | `GET_DATA_RANGE` | read-only backlog window query |
| `0x03` | `TOGGLE_REALTIME_HR` | live stream toggle, no flash access |
| `0x3F` | `SEND_R10_R11_REALTIME` | live HR + IMU |
| `0x6A` | `TOGGLE_IMU_MODE` | live IMU |
| `0x6B` | `ENABLE_OPTICAL_DATA` | wrist-gated optical, live only |
| `0x6C` | `TOGGLE_OPTICAL_MODE` | live optical |

**Permanently forbidden — not behind a flag, absent from the codebase:**

| Opcode | Command | Why |
|---|---|---|
| `0x16` | `SEND_HISTORICAL_DATA` | starts flash drain |
| `0x17` | `HISTORICAL_DATA_RESULT` | the ACK that advances the shared cursor |
| `0x21` | `SET_READ_POINTER` | moves the shared cursor |
| `0x14` | `ABORT_HISTORICAL_TRANSMITS` | only meaningful if draining |
| `0x9A` | `TOGGLE_PERSISTENT_R21` | documented footgun — forces optical, sticks the LED on |
| `0x1D` | `REBOOT_STRAP` | hard reset |
| `0x0A` | `SET_CLOCK` | writes the band's RTC |

If a `0x2F` historical packet or `0x31` sync marker ever arrives unsolicited, the app
**logs and discards it and never ACKs**. No ACK means no cursor movement.

Additionally: **read-only by construction** — no write path exists to any band setting,
alarm, or clock. The app cannot modify your band.

### What we stream

Enable sequence: `SEND_R10_R11_REALTIME (0x3F)` + `ENABLE_OPTICAL_DATA (0x6B)`
[+ `TOGGLE_IMU_MODE (0x6A)`].

- **R10** — packet `0x2B`, record `0x0A`, ~1.9 KB per record across several notifications:
  HR + IMU. Compact HR also arrives on `0x28`; the two agree within ±1 bpm on a worn band,
  which gives us a free cross-check.
- **R21** — 6-channel optical, ~1244 B: the pulse waveform, and the **only** source of true
  respiratory rate (amplitude/baseline modulation).
- **r22** (Gen 5) — reported at ~6 300 frames/min behind a ~15-step configuration sequence,
  carrying HR, RR intervals, and accelerometer. This is the highest-value channel and the
  least documented. The spike measures it before we commit to it.

Events (`0x30`) we consume passively: `9 WRIST_ON` / `10 WRIST_OFF` (authoritative wear
detection), `3 BATTERY_LEVEL`, `7`/`8` charging, `23 BLE_BONDED`, `13 RTC_LOST`, `14 DOUBLE_TAP`.

### Gen 5 discovery spike — before any decoder work

The Gen 5 record layouts are not published. Ship a spike first, not a guess:

1. Connect, enumerate the `fd4b…` service, subscribe to `0003/0004/0005/0007`.
2. Send `GET_HELLO_HARVARD` with write-with-response; confirm the CRC-16/MODBUS envelope
   round-trips.
3. Log **every raw frame to `ble_inbox` untouched** for a 30-minute worn session.
4. Offline: histogram packet types, hunt the HR byte by correlating against a chest strap or
   the WHOOP app's live HR, locate RR arrays by looking for plausible 600–1400 ms i16 runs,
   locate accel by finding f32 triples with magnitude ≈ 1 g at rest.
5. Write the Gen 5 layout into `docs/PROTOCOL-GEN5.md`, with a confidence rating per field.

Gen 4's type-24 layout is the *hypothesis* to test against, not the answer:
`[7:11]` u32 LE unix ts · `[17]` u8 HR · `[18]` rr_count · `[19:19+2n]` i16 LE RR ms ·
`[29]` u16 green PPG · `[31]` u16 red/IR · `[36:48]` f32×3 accel · `[51]` skin contact
0–198 · `[64]`/`[66]` red/IR ADC · `[68]` skin temp ADC · `[70]` ambient light · `[88]` RHR
baseline. Bytes `[76]`/`[78]` are bit-constant on Gen 4 (3073/3074) — trailer, not sensor.

**Only decode a field once the spike confirms it.** Never fabricate a value; every derived
metric carries a confidence score, and absent input yields "unavailable", not zero.

---

## Constraints from the free Apple ID

Personal Team grants **no entitlement-backed capabilities**:

❌ iCloud · ❌ App Groups · ❌ Push · ❌ HealthKit · ❌ Associated Domains

App Groups being blocked also means **no home-screen or Lock Screen widget** — a widget is a
separate process and needs a shared container to read the database.

✅ Works fine: Background App Refresh and `bluetooth-central` background mode (both are
Info.plist `UIBackgroundModes` keys, not entitlements), Keychain, CoreBluetooth, Files sharing.

⚠️ **The app expires every 7 days.** Re-plug and re-run from Xcode. Costs you no data —
WHOOP retains full history and sync is watermark-driven, so a relaunch after a two-week gap
backfills the gap automatically. The Today screen shows a countdown banner from day 5.

**Export path (replaces the iCloud snapshot I originally suggested):** the database and
exports live in `Documents/` with `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace`.
That makes the folder browsable in **Files → On My iPhone → ReflexWhoop** and draggable from
**Finder** over the cable. The in-app Export button also opens a share sheet, so one tap
saves into iCloud Drive where the Mac picks it up.

---

## Architecture

```
reflex-whoop/
  ReflexWhoop.xcodeproj
  ReflexWhoop/
    App/          ReflexWhoopApp, RootView, DIContainer
    Auth/         WhoopAuth, TokenStore (Keychain), OAuthConfig
    Api/          WhoopClient, RateLimiter, Paginator, Models/
    Ble/          BandSession, Framing (CRC16/CRC32, length-based reassembler),
                  OpcodeAllowlist, Decoders/ (R10, R21, r22, Events, Hello), StreamRecorder
    Ingest/       Inbox, Normalizer, ChangeDetector          ← both sources land here
    Store/        Database (GRDB), Migrations/, DAO/, TimeSeries/ (ChunkCodec, ChunkStore)
    Sync/         ApiSyncEngine, SyncPolicy, BackgroundSync, SyncLog
    Analysis/     Baselines, Trends, Correlations, Anomalies, Readiness,
                  Hrv (rMSSD/SDNN/pNN50/DFA-α1), Respiration, Stats
    Export/       Exporter (CSV + VACUUM INTO snapshot + JSONL + manifest)
    UI/           Today, Trends, Insights, Live, Data, Settings, Charts/, Components/
  ReflexWhoopTests/    fixtures + unit tests
  mcp-server/          Python MCP server (Mac)
  docs/                PROTOCOL-GEN5.md, SCHEMA.md, DECISIONS.md
```

Everything below `Ingest/` is pure Swift with no SwiftUI import — it unit-tests without a
simulator or a band.

---

## Storage design

SQLite via **GRDB.swift**, at `Documents/reflexwhoop.sqlite`. Five layers, each with one job.

### Layer 1 — Inbox (append-only, lossless, source-agnostic)

```sql
ingest_inbox(
  seq INTEGER PRIMARY KEY,       -- monotonic
  source TEXT,                   -- 'api' | 'ble'
  kind TEXT,                     -- endpoint path, or BLE packet type
  received_at INTEGER,
  payload BLOB,                  -- API: JSON. BLE: raw frame bytes, pre-decode.
  codec TEXT,                    -- 'raw' | 'zlib'
  decoded_at INTEGER,            -- NULL until the normalizer has processed it
  decoder_version INTEGER
)
```

**Write to the inbox first, decode second.** Stolen from whoop-stats' webhook inbox pattern
and it matters even more here:

- A decoder bug is never data loss — fix the decoder, bump `decoder_version`, replay the inbox.
- BLE notifications arrive faster than we can parse them; the CoreBluetooth delegate does a
  blob append and returns, keeping the queue drained.
- The Gen 5 spike *is* the inbox replaying against successive decoder guesses.

API payloads are stored zlib-compressed (`Compression` framework, no dependency). WHOOP JSON
compresses ~8×; four years of API history is ~9 MB raw, ~1 MB compressed. Irrelevant either
way, but free.

### Layer 2 — Normalized records (API)

`cycles` · `recoveries` · `sleeps` · `sleep_stage_summary` · `sleep_need` · `workouts` ·
`workout_zone_durations` · `body_measurements` · `profile`.

Every row keeps `score_state`, `created_at`, `updated_at`, `timezone_offset`, `source`,
`inbox_seq`, and `content_hash`; sleeps and workouts also keep `activity_v1_id`.

All writes are `INSERT … ON CONFLICT(id) DO UPDATE`, so retroactive re-scoring overwrites
cleanly and never duplicates.

**`content_hash` change detection:** hash the normalized field set. If unchanged, skip the
write *and* skip marking the day dirty for recomputation. With a 7-day lookback re-pull,
~95% of fetched records are unchanged — this makes the overlap nearly free.

### Layer 3 — Time series (BLE) — the part that actually needs engineering

One row per sample would be catastrophic: a 100 Hz live session produces 360 000 samples per
hour per channel. Instead, **columnar chunks with delta encoding**, which is what TimescaleDB
does for whoop-stats, done by hand because SQLite has no equivalent.

```sql
ts_chunk(
  channel TEXT,          -- 'hr' | 'rr' | 'accel_x/y/z' | 'ppg_green' | 'ppg_red' | 'ppg_ir'
                         -- | 'skin_temp_adc' | 'ambient' | 'skin_contact' | 'rhr_baseline'
  session_id TEXT,
  bucket_start INTEGER,  -- epoch seconds, 1-hour buckets
  sample_count INTEGER,
  nominal_hz REAL,
  first_ts INTEGER, last_ts INTEGER,
  encoding TEXT,         -- 'delta_zigzag_varint' | 'raw_u16'
  codec TEXT,            -- 'lzfse' | 'zlib' | 'none'
  min_val REAL, max_val REAL, mean_val REAL,   -- summary, lets charts skip decoding
  blob BLOB,
  PRIMARY KEY(channel, session_id, bucket_start)
)
```

Encoding pipeline per channel: quantize → delta → zigzag → varint → LZFSE.

- HR is an integer that moves ±2 bpm/s: ~3–4 bits/sample after delta.
- Accel f32 quantized to milli-g i16 before delta — lossless at the sensor's real precision,
  half the bytes.
- PPG is noisy and compresses worst (~8–10 bits/sample); it dominates the budget.
- **RR intervals get their own chunk channel**, not a row table. 600–1400 ms values with
  small deltas: ~6 bits each, ~3 KB/hour, ~26 MB/year even at continuous wear. Cheap and
  the highest-value data in the system.

`ChunkCodec` is a pure function with round-trip property tests: encode(decode(x)) == x for
random inputs, every channel, every edge case (empty, single sample, saturating deltas).

**Sessions** (`ble_sessions`) record start/end, mode, band firmware, battery at start/end,
channels captured, sample counts, and byte totals — so the Data screen can show exactly what
a session cost you.

### Layer 4 — Derived (recomputable, versioned)

`daily_metrics` · `baselines` · `correlations` · `anomalies` · `session_metrics` ·
`ts_rollup_minute`.

Two rules borrowed from OpenStrap:

1. **Every derived row carries `algo_version` and `confidence`.** Bumping an algorithm's
   version invalidates and recomputes rather than silently overwriting last year's numbers
   with a new formula's output. You can always tell which version produced a number.
2. **Never fabricate.** Missing input yields `NULL` + a reason, never a zero, never an
   interpolation the UI can't distinguish from a measurement.

**Scoped recomputation:** a `dirty_days(day, reason)` queue is populated by the change
detector. Recompute touches only affected dates plus the rolling-window tail that depends on
them, never the whole history. Baselines use a 3-day settling lookback — the same trick
whoop-stats' continuous aggregates use.

**`ts_rollup_minute`** is what charts actually read: per-minute min/max/mean/count per
channel. A one-year HR chart reads ~525 k pre-aggregated rows instead of decoding 31 M
samples. Chunks are only decoded when you zoom into a specific window.

### Layer 5 — Control

`sync_state(resource, last_synced_at, last_cursor, backfill_complete)` ·
`pending_scores(resource, id, first_seen_at, attempts)` · `sync_log` · `dirty_days` ·
`schema_meta(version, algo_versions_json)`.

### SQLite configuration

`journal_mode=WAL` · `synchronous=NORMAL` · `temp_store=MEMORY` · `mmap_size=256MB` ·
`auto_vacuum=INCREMENTAL` (with a periodic incremental vacuum, since blobs churn) ·
`page_size=4096`. Batch inserts inside a single transaction; GRDB's prepared-statement cache
handles the rest. Indices on `(start)`, `(end)`, `cycle_id`, `score_state`,
`(channel, bucket_start)`, `dirty_days(day)` — and nothing more, because every index taxes
the write path that BLE hammers.

### Storage reality check — "keep everything forever"

You chose to keep everything. With live-stream-only BLE, cost scales with **how much you
stream**, not with wall-clock time:

| Scenario | Est. compressed |
|---|---|
| API data, 4 years of history | ~10 MB total |
| RR intervals, continuous | ~26 MB/year |
| HR at 1 Hz, continuous | ~4 MB/year |
| A 1-hour workout session, all channels incl. raw PPG | ~50–150 MB → **~10–25 MB compressed** |
| An 8-hour overnight session, all channels | **~80–200 MB compressed** |

Nightly overnight sessions with full raw PPG would run to tens of GB per year. That is the
one number that could bite you.

So: **keep-everything is the default and nothing is auto-deleted**, but the app makes the
cost visible and reversible —

- **Storage screen** breaking down bytes by channel, by session, by month.
- A configurable **soft budget** (default 5 GB) that warns rather than deletes.
- **Per-channel capture toggles** on the Live screen — "HR + RR only" is ~1% the cost of
  "everything including raw PPG", and for a nightly HRV recording it loses you nothing.
- **Optional post-hoc PPG discard** per session, once derived metrics are computed, as an
  explicit button. Never automatic.

The spike measures the true byte rate before any of these defaults are fixed.

---

## System design decisions worth naming

- **Inbox-first ingestion** for both sources — decode is always replayable.
- **Adaptive polling instead of fetch-everything** (whoop-stats' cadence, adapted to iOS):
  each resource has a staleness budget — workouts 30 min, sleep 1 h, cycles 4 h, recovery
  1 h, profile/body 24 h. Foreground sync fetches only what's stale. A typical sync is 2–4
  requests, not 12.
- **7-day lookback + upsert** on incremental sync, because WHOOP re-scores retroactively.
- **Content-hash change detection** so the lookback overlap costs nothing downstream.
- **Scoped recompute** via `dirty_days` — analysis never rescans history.
- **Versioned algorithms + confidence scores** on every derived value.
- **Single-writer discipline:** one GRDB `DatabaseQueue` writer; BLE notifications and API
  sync both funnel through it via actor-isolated append. No concurrent-write corruption.
- **Backpressure on BLE:** a bounded ring buffer between the CoreBluetooth delegate and the
  inbox writer. If the writer falls behind, count drops in `ble_sessions` and surface them —
  never silently lose samples without recording that you did.
- **Cross-source validation:** compare BLE-derived RHR and HRV against the API's nightly
  numbers on overlapping nights. Persistent divergence means the decoder is wrong, and the
  Data screen shows the delta. Free correctness signal.

---

## Analysis engine

Pure Swift, no dependencies, recomputed for dirty days after each sync or session.

**From the API (daily grain):**
- Baselines — 30/60-day rolling mean + SD for HRV, RHR, respiratory rate, skin temp, SpO2;
  z-scores and deviation bands. Rows with `user_calibrating = true` are excluded and flagged.
- Trends — 7/28/90-day rolling means, WoW and MoM deltas, weekday effects, cumulative sleep
  debt, sleep-midpoint consistency (SD of bedtime), PRs by `sport_name`.
- Load balance — acute (7 d) vs chronic (28 d) strain ratio, ACWR-style, labeled as a
  training-load heuristic and not a medical signal.
- Correlations — lagged Spearman rho of next-day recovery against prior-day strain, sleep
  duration, efficiency, bedtime, consistency, REM %, SWS %, disturbance count, respiratory
  rate, skin-temp deviation, acute:chronic ratio. Reports **rho, n, and a
  Benjamini–Hochberg-corrected p** — a dozen predictors on one person's data manufactures
  false positives, and the UI says so. n < 30 renders greyed as "not enough data yet".
- Anomalies — multi-signal illness flag (respiratory rate ↑, skin temp ↑, RHR ↑, HRV ↓
  together beyond 1.5 SD) and single-metric > 2 SD excursions.
- Readiness — our composite of HRV z, RHR z, sleep-debt ratio, acute:chronic load. Labeled
  **"ReflexWhoop score — not WHOOP's"** everywhere.

**From BLE (things the API structurally cannot give you):**
- **Full HRV suite from RR intervals** — rMSSD, SDNN, pNN50, RMSSD-over-time, and **DFA-α1**
  for aerobic-threshold estimation. Artifact correction on the RR series first (ectopic beat
  rejection by median-filter deviation), with the rejection rate reported as the confidence
  score.
- **Intra-night HRV curve** — per-30-minute rMSSD across a night, instead of one number.
  Shows *when* recovery happened.
- **Intra-workout HRV and HR recovery** — HRR60 after intervals, drift, decoupling.
- **Respiratory rate from the R21 PPG waveform** — amplitude/baseline modulation. Ours,
  independent of WHOOP's.
- **Activity counts and posture from accelerometer** — sleep-movement index, wake detection
  cross-check.
- **Signal quality** — skin-contact quality and PPG SNR per session, so you know which
  recordings to trust.

Unit-tested against synthetic series with planted answers: a known-rho correlation must be
recovered within tolerance, and a pure-noise series must produce **no** surviving finding
after BH correction.

---

## UI / UX

Black and champagne ("Onyx"), four tabs: **Today · Trends · Band · Archive**. The full
visual system, component list and copy rules are in
`docs/superpowers/specs/2026-09-13-onyx-redesign-design.md`; the screens were designed
and reviewed on the design canvas before they were built.

### Principles

1. **The top of Today answers one question in one sentence.** Recovery, its band, and
   what that means for the day. A day flagged for possible illness always says to keep
   it easy.
2. **No number appears without the person's own normal.** Range strips, recovery zones
   and chart bands all show the 60-day baseline mean ± 1 SD; unusual means 2 SD or more,
   the same threshold `AnomalyEngine` uses.
3. **Missing stays missing.** A night without a reading says so; nothing is drawn as
   zero, and chart lines break where readings stop.
4. **Confidence is visible, never implied.** Patterns shows r and corrected p, gives a
   direction only for moderate or strong results, and shows how many days each
   predictor still needs.
5. **Never colour-only.** Every coloured state also carries a word. Text follows Dynamic
   Type, and charts carry VoiceOver descriptions.
6. **Readiness is hidden** until its sleep-debt input is rebuilt (DECISIONS.md).

### Screens

**Today** — recovery hero with its verdict and zones, strain on WHOOP's 0–21 scale, last
night's sleep with stage totals, and the overnight vitals against their normal. With no
WHOOP scores, or after a membership ends, it shows today's heart rate from the band
instead of presenting an old day as today.

**Trends** — every metric's sparkline for 30 days, 90 days, a year or all history, each
opening to its full history. Patterns (correlations with next-morning recovery) and
Unusual days live here.

**Band** — live heart rate and the last 20 minutes, the Keep recording setting, past
recordings with one-minute charts, and Signal details for decoding work.

**Archive** — what the phone holds, the WHOOP account and band sources, Export a copy,
Rebuild heart-rate history, and what the app never does.

**First run** — shown only to an install with no data and no account: choose sources,
a Bluetooth primer before the system prompt, WHOOP credentials, and the first sync.

---

## Export and MCP

**Export** writes `Documents/exports/<timestamp>/`:
- CSV per normalized and derived table,
- `reflexwhoop.sqlite` — a **`VACUUM INTO`** snapshot (safe to copy from a live WAL database,
  unlike a plain file copy),
- `raw_api.jsonl` and `ble_sessions/<id>.bin` — untouched payloads,
- `manifest.json` — export time, row counts, byte counts, schema version, algo versions,
  date range.

Then a share sheet → iCloud Drive → your Mac. Also reachable via Files and Finder.

**Parquet conversion runs on the Mac**, not the phone — there is no maintained pure-Swift
Parquet writer worth depending on. `mcp-server/tools/to_parquet.py` does it with
pandas + pyarrow in a few lines.

**MCP server** (`mcp-server/`, Python) opens the snapshot **read-only**
(`file:…?mode=ro`) so Claude can never mutate your history. Tools:

| Tool | Purpose |
|---|---|
| `schema()` | tables + columns, so Claude writes its own SQL |
| `query(sql)` | read-only SQL, statement allowlist, row cap, timeout |
| `daily_summary(range)` | joined recovery + sleep + strain per day |
| `trend(metric, window, range)` | rolling series |
| `correlations(min_n)` | precomputed table with caveats attached |
| `workouts(sport, range)` | sessions with zone durations |
| `hrv_session(session_id)` | per-session RR-derived HRV suite |

Registered via `claude mcp add`; `README.md` gives the exact command.

---

## Build order

**Phase 1 — foundation** (works with no band, no network)
1. Xcode project, GRDB, migrations, DAOs, `ChunkCodec` with round-trip property tests.
2. Inbox + normalizer + change detector, tested against fixture JSON.

**Phase 2 — API collector** (this alone is a useful app)
3. Auth: setup screen, `ASWebAuthenticationSession`, Keychain, atomic rotating refresh.
4. API client: models, paginator, rate limiter, retry.
5. Sync engine: backfill → incremental → pending re-fetch, adaptive cadence, background task.

**Phase 3 — analysis + UI**
6. Baselines, trends, correlations, anomalies, readiness, `dirty_days` scoping.
7. Today → Trends → Insights → Data → Settings.

**Phase 4 — BLE** (the exploratory part, deliberately last)
8. **Gen 5 discovery spike** — connect, log raw frames, verify the CRC-16/MODBUS envelope,
   map fields, write `docs/PROTOCOL-GEN5.md`. Output is a document, not shipping code.
9. Framing + opcode allowlist + allowlist unit test. Decoders for confirmed fields only.
10. Session recorder → inbox → chunk store, with backpressure and drop accounting.
11. Live screen; HRV suite; cross-source validation.

**Phase 5 — hand-off**
12. Export; MCP server; Parquet converter.

Phases 1–3 ship a complete, low-risk product. Phase 4 is where the novel value is and where
the schedule risk lives — putting it last means a firmware change or an unmappable packet
format costs you an increment, not the project.

---

## Verification

**Prerequisite (manual, once):** create the app at developer.whoop.com → Developer Dashboard,
redirect URI `reflexwhoop://oauth/callback`, all seven scopes, copy client id + secret.

1. **Codec** — `xcodebuild test`: `ChunkCodec` round-trip property tests over random inputs
   per channel, including empty, single-sample, and saturating-delta cases. Runs with no
   device.
2. **Storage** — migration and DAO round-trip tests against fixtures.
3. **Auth** — on device, paste credentials, complete WHOOP login, confirm Settings shows your
   name and email. Hit the debug "expire token" button and confirm silent refresh.
4. **Rate limiting** — unit test drives the limiter with synthetic 429s and asserts it waits
   for `X-RateLimit-Reset`. The live backfill must show zero 429s in `sync_log`.
5. **Backfill accuracy** — run to completion, then cross-check against the WHOOP app: cycle
   count ≈ days since you got the strap, and pick 3 random days and 3 workouts and compare
   recovery %, HRV, sleep duration and workout strain **digit for digit**.
6. **Resumability** — kill the app mid-backfill; relaunch; confirm it resumes from checkpoint
   and total row counts match a clean run.
7. **Re-scoring** — after a night, confirm the `PENDING_SCORE` record updates in place:
   `SELECT id, COUNT(*) … GROUP BY id HAVING COUNT(*) > 1` must return nothing.
8. **Analysis** — planted-correlation synthetic series recovers the known rho within
   tolerance; pure-noise series yields no finding surviving BH correction.
9. **BLE safety (do this before any live session)** — unit test asserts the allowlist rejects
   every forbidden opcode. Then run a 30-min session and confirm in the frame log that **no
   `0x16`/`0x17`/`0x21` was ever transmitted** and no `0x31` marker was ACKed. Immediately
   afterwards, open the official WHOOP app and confirm it syncs normally and your scores are
   intact. Repeat this check after the first overnight session.
10. **BLE decode correctness** — during a live session, compare decoded HR against the WHOOP
    app's live HR (must agree within ±1 bpm, per the R10/`0x28` cross-check) and against a
    chest strap if you have one. Compare a night's BLE-derived rMSSD and RHR against the
    API's numbers for the same night; a persistent gap means the decoder is wrong.
11. **Backpressure** — stream all channels for an hour and confirm `ble_sessions.dropped = 0`;
    if not, the ring buffer or writer needs sizing.
12. **Storage** — after a full-channel session, check the Storage screen's byte accounting
    against the actual file growth, and confirm the estimates in this plan.
13. **Export** — export, open the CSVs, run `sqlite3 reflexwhoop.sqlite "PRAGMA
    integrity_check;"` on the Mac, confirm row counts match `manifest.json`.
14. **MCP** — `claude mcp add`, then ask Claude *"what was my average recovery on days after I
    slept under 6 hours?"* and verify against a hand-written SQL query.

---

## Known limitations, stated up front

- **Peak-tier metrics are not obtainable.** WHOOP Age, Hormonal Insights, Blood Pressure,
  Journal, Strain Coach — not in the API, not on the band. Our readiness score is ours.
- **BLE gives no scores.** Recovery, strain and sleep stages are computed in WHOOP's cloud;
  the band only holds signal. BLE complements the API, it does not replace it.
- **Gen 5 protocol is reverse-engineered and undocumented.** A firmware update can break the
  decoder overnight. The inbox means you keep the bytes and fix the decoder; it does not mean
  the decoder keeps working.
- **Live-stream-only means gaps.** No BLE data accrues unless you start a session. The API
  covers 24/7; BLE covers what you choose to record.
- **The app expires every 7 days** on a free Apple ID. No data lost, but sync and sessions
  stop until you re-plug.
- **Background BLE is opportunistic.** `bluetooth-central` keeps a *connected* peripheral
  delivering in background, but iOS can still suspend or kill the app. Long overnight
  sessions will sometimes end early; the session record says so.
- **The client secret lives on the device.** Single-user personal app — Keychain, never in the
  binary, never in git.
- **Correlations on one person's data are suggestive, not causal**, and the UI must not imply
  otherwise.
