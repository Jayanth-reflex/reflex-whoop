# ReflexWhoop

Personal WHOOP 5.0 data collector, analyzer, and local store for iPhone. Pulls your
own data from two sources — the WHOOP Cloud API and (later) direct BLE to the band —
stores it losslessly on-device, and computes the trends, baselines, and correlations
WHOOP's own app doesn't expose.

Full design: [`docs/design.md`](docs/design.md). Notable implementation decisions:
[`docs/DECISIONS.md`](docs/DECISIONS.md).

Personal use, single member. Not submitted to the App Store.

## Status

**Phase 1 (foundation) complete.** Storage schema, `ChunkCodec`/`ChunkStore` for BLE
time series, the ingest inbox, and the API-model normalizer are built and tested
(29/29 tests passing). The app builds and runs — Today/Trends/Insights/Live/Data/
Settings tabs exist as placeholders pending their phase.

**Not yet built:** OAuth + WHOOP API client + sync engine (Phase 2), the analysis
engine and real UI (Phase 3), BLE (Phase 4, including a Gen 5 protocol discovery
spike — WHOOP 5.0's BLE protocol is not publicly documented), export + MCP server
(Phase 5).

## Requirements

- Xcode 26+, an iPhone on a free or paid Apple ID, a cable.
- A WHOOP developer app once Phase 2 lands: create one at
  [developer.whoop.com](https://developer.whoop.com), set the redirect URI to
  `reflexwhoop://oauth/callback`, and enable all seven scopes
  (`read:profile read:body_measurement read:cycles read:recovery read:sleep
  read:workout offline`).

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

Or just open `ReflexWhoop.xcodeproj` in Xcode, pick your personal team under
Signing & Capabilities for both targets, plug in your iPhone, and run. On a free
Apple ID the installed build expires after 7 days — re-run from Xcode to refresh it;
no data is lost, sync is watermark-driven and backfills the gap.

## Testing

```bash
xcodebuild test -project ReflexWhoop.xcodeproj -scheme ReflexWhoop \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Project layout

```
ReflexWhoop/
  App/          composition root + SwiftUI app entry point
  Auth/         OAuth (Phase 2)
  Api/          WHOOP v2 API models + client (models done, client is Phase 2)
  Ble/          direct-to-band Bluetooth (Phase 4)
  Ingest/       append-only inbox + normalizer — both data sources land here first
  Store/        SQLite (GRDB): migrations, DAOs, BLE time-series chunk codec/store
  Sync/         API sync engine (Phase 2)
  Analysis/     baselines, trends, correlations, HRV suite (Phase 3)
  Export/       CSV/SQLite/JSONL export (Phase 5)
  UI/           SwiftUI screens
ReflexWhoopTests/  unit tests + WHOOP API fixture JSON
mcp-server/        Python MCP server for Claude to query your data (Phase 5)
docs/              design doc, decisions log
scripts/           project generator (see Building, above)
```
