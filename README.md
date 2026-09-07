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
iPhone** (not just the simulator — see "Verification" below). 55/55 tests passing.

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

**Not yet built:** direct-to-band BLE (Phase 4, starting with a Gen 5 protocol
discovery spike — WHOOP 5.0's BLE protocol is not publicly documented), export +
MCP server (Phase 5).

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
  Ble/          direct-to-band Bluetooth (Phase 4, not yet built)
  Ingest/       append-only inbox + normalizer — both data sources land here first
  Store/        SQLite (GRDB): migrations, DAOs, BLE time-series chunk codec/store
  Sync/         backfill / incremental / pending-score-refetch sync engine
  Analysis/     daily_metrics builder, baselines, readiness, anomalies, correlations
  Export/       CSV/SQLite/JSONL export (Phase 5, not yet built)
  UI/           SwiftUI screens — Today/Trends/Insights are real; Live/Data are
                Phase 1/4 placeholders and working row-count views respectively
ReflexWhoopTests/  unit tests + WHOOP API fixture JSON (55 tests)
mcp-server/        Python MCP server for Claude to query your data (Phase 5)
docs/              design doc, decisions log
scripts/           project generator (see Building, above)
```
