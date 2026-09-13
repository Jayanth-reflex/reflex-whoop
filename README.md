# ReflexWhoop

Personal WHOOP 5.0 data collector, analyzer, and local store for iPhone. Pulls your
own data from two sources — the WHOOP Cloud API and (later) direct BLE to the band —
stores it losslessly on-device, and computes the trends, baselines, and correlations
WHOOP's own app doesn't expose.

Full design: [`docs/design.md`](docs/design.md). Notable implementation decisions:
[`docs/DECISIONS.md`](docs/DECISIONS.md).

Personal use, single member. Not submitted to the App Store.

## Status

**Phases 1-3 complete and verified live against a real WHOOP account and a real
iPhone** (not just the simulator — see "Verification" below). Phase 4 (BLE) is
underway with one confirmed sensor decode, now normalized into queryable time
series; Phase 5 (export + MCP) is built and working. 117/117 tests passing,
Debug and Release configurations both building clean.

An architecture review — [`docs/ADR-001-data-sovereignty.md`](docs/ADR-001-data-sovereignty.md)
— reframed the project around the fact that every asset here except the local
archive is leased from WHOOP. Its decision (source-agnostic archive; every
source can be absent; the archive is never destroyed) is implemented, and the
boundary it depends on is specified in
[`docs/NEUTRAL-CONTRACT.md`](docs/NEUTRAL-CONTRACT.md).

- **Phase 1 (foundation):** storage schema, `ChunkCodec`/`ChunkStore` for BLE time
  series, the ingest inbox, and the API-model normalizer.
- **Phase 2 (collector):** OAuth2 against the real WHOOP API (`ASWebAuthenticationSession`,
  Keychain-backed token storage with atomic rotation handling), the rate-limited API
  client, and the sync engine (per-resource backfill, 7-day re-scoring lookback,
  pending-score re-fetch, adaptive staleness budgets, manual/background/foreground
  triggers).
- **Phase 3 (analysis + UI):** `daily_metrics` built from the normalized layer,
  30/60-day rolling baselines with z-scores, a labeled ReflexWhoop readiness
  composite (HRV/RHR/sleep-debt/load-balance — explicitly not WHOOP's own score),
  illness/excursion anomaly detection, and lagged Spearman correlations against
  next-day recovery with Benjamini-Hochberg correction across the whole predictor
  batch. Today/Trends/Insights are real screens now, not placeholders.

- **Phase 4 (BLE, in progress):** direct CoreBluetooth connection to the band
  over its custom `fd4b…` service. The Gen 5 envelope is fully reverse-engineered
  and confirmed against two real worn sessions (see
  [`docs/PROTOCOL-GEN5.md`](docs/PROTOCOL-GEN5.md)) — 8-byte header, CRC-16 +
  CRC-32 framing, no padding. `OpcodeAllowlist` is the single choke point every
  outgoing command passes through: it structurally cannot send a
  flash-cursor-moving opcode, enforced by tests, not just convention. One
  sensor field is confirmed and decoded (realtime heart rate, `0x28` records);
  IMU and optical (R21/r22 — the higher-value, undocumented channels) are
  enabled in the spike but not yet mapped.
- **Phase 5 (export + MCP):** `Exporter` writes CSVs, a `VACUUM INTO` SQLite
  snapshot, raw API/BLE payload dumps, and a manifest to `Documents/exports/`,
  wired to a Data-tab button with a share sheet. `mcp-server/` (Python) opens
  that snapshot read-only and gives Claude on your Mac `schema`/`query`/
  `daily_summary`/`trend`/`correlations`/`workouts`/`hrv_session` tools — see
  [`mcp-server/README.md`](mcp-server/README.md) for setup.

**Not yet built:** R21/r22 sensor decoding, and therefore the HRV suite
(rMSSD/SDNN/pNN50/DFA-α1) and true respiratory rate — all four need a
beat-to-beat RR channel that no confirmed Gen 5 decoder produces yet. Those
columns exist and stay `NULL` rather than being filled with a substitute. Also
outstanding: the Parquet conversion step beyond the CLI script, and an alarm
threshold on the decode canary.

### Verification

Phases 2 and 3 were each confirmed by pulling the live on-device SQLite database
(`xcrun devicectl device copy from --domain-type appDataContainer`, WAL file
included) off a real iPhone running a real, currently-subscribed WHOOP account —
not just unit tests. Phase 2: a full backfill landed 243 real records (cycles,
recoveries, sleeps, workouts) with zero sync errors. Phase 3: 63 real days were
analyzed into 634 baselines, 9 correlations, and 21 anomalies, correctly reporting
"weak/insufficient" on every correlation given only ~2 months of history rather than
manufacturing false significance.

## Requirements

- Xcode 26+, an iPhone, a cable.
- **An Apple ID signed into Xcode** (Xcode → Settings → Accounts) — free (Personal
  Team) or paid both work; free just means the installed build expires after 7 days
  (see "Building," below) and the first install needs one manual on-device trust step
  (Settings → General → VPN & Device Management → trust your Apple ID).
- A WHOOP developer app: create one at
  [developer.whoop.com](https://developer.whoop.com), set the redirect URI to
  `reflexwhoop://oauth/callback`, and enable all six listed scopes
  (`read:profile read:body_measurement read:cycles read:recovery read:sleep
  read:workout`) — see [`docs/DECISIONS.md`](docs/DECISIONS.md) on the seventh,
  `offline`, which isn't a dashboard checkbox at all.

## Building

```bash
# Regenerate the .xcodeproj after adding/removing source files (no xcodegen/tuist
# available in the dev environment this was built in — see docs/DECISIONS.md):
gem install --user-install xcodeproj   # once
ruby scripts/generate_project.rb

# Resolve the GRDB.swift package and build:
xcodebuild -resolvePackageDependencies -project ReflexWhoop.xcodeproj -scheme ReflexWhoop
xcodebuild build -project ReflexWhoop.xcodeproj -scheme ReflexWhoop \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Or just open `ReflexWhoop.xcodeproj` in Xcode, plug in your iPhone, and run — signing
is already wired to a hardcoded `DEVELOPMENT_TEAM` in `scripts/generate_project.rb`
(see [`docs/DECISIONS.md`](docs/DECISIONS.md) if you're building under a different
Apple ID and need to change it). On a free Apple ID the installed build expires after
7 days — re-run from Xcode (or `xcrun devicectl device install app` +
`process launch`) to refresh it; no data is lost, sync is watermark-driven and
backfills the gap. The very first install also needs one manual on-device trust step:
Settings → General → VPN & Device Management → trust your Apple ID.

## Testing

```bash
xcodebuild test -project ReflexWhoop.xcodeproj -scheme ReflexWhoop \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Project layout

```
ReflexWhoop/
  App/          composition root + SwiftUI app entry point
  Auth/         OAuth2 against the WHOOP API — token store, Keychain, refresh
  Api/          WHOOP v2 API models + rate-limited client
  Ble/          direct-to-band Bluetooth — envelope, opcode allowlist, decoders
                (Phase 4, in progress: HR confirmed, R21/r22 not yet mapped)
  Ingest/       append-only inbox + normalizer — both data sources land here first
  Store/        SQLite (GRDB): migrations, DAOs, BLE time-series chunk codec/store
  Sync/         backfill / incremental / pending-score-refetch sync engine
  Analysis/     daily_metrics builder, baselines, readiness, anomalies, correlations
  Export/       CSV/SQLite snapshot/JSONL/manifest export (Phase 5, done)
  UI/           SwiftUI screens — Today/Trends/Insights/Live/Data are all real;
                Live shows the BLE spike, Data has the Export button
ReflexWhoopTests/  unit tests + WHOOP API fixture JSON (89 tests)
mcp-server/        Python MCP server for Claude to query your data — done, see
                   mcp-server/README.md
docs/              design doc, decisions log
scripts/           project generator (see Building, above)
```
