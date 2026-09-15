# AGENTS.md

Guidance for coding agents working in this repository. Humans: start with
[README.md](README.md).

ReflexWhoop is a SwiftUI iPhone app that keeps a WHOOP member's data on-device: it syncs
the WHOOP API, records live heart rate from the band over read-only Bluetooth, and
analyses both from a local SQLite archive. A Python MCP server in `mcp-server/` queries
exported snapshots.

| Read before | Doc |
|---|---|
| any change | this file |
| touching structure, storage, sync or analysis | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) |
| touching `ReflexWhoop/Ble/` | [docs/PROTOCOL-GEN5.md](docs/PROTOCOL-GEN5.md), especially Safety rails |
| touching `ReflexWhoop/UI/` | [docs/DESIGN-SYSTEM.md](docs/DESIGN-SYSTEM.md) |
| second-guessing something odd | [docs/DECISIONS.md](docs/DECISIONS.md) |

## Commands

```bash
# After adding, removing or renaming any file. Never hand-edit the .xcodeproj.
gem install --user-install xcodeproj   # once
ruby scripts/generate_project.rb

# Build and test (Xcode 26+, iOS 26 simulator)
xcodebuild test -project ReflexWhoop.xcodeproj -scheme ReflexWhoop \
  -destination 'platform=iOS Simulator,name=iPhone 17'

# One test class or method
xcodebuild test -project ReflexWhoop.xcodeproj -scheme ReflexWhoop \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:ReflexWhoopTests/MetricTests/testSkinTemperatureFollowsTheTemperatureUnit

# MCP server
cd mcp-server && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
```

The generator writes identical output for an unchanged tree; a regenerate that changes
`project.pbxproj` without a file being added or removed is a bug. To sign under another
Apple ID: `DEVELOPMENT_TEAM=… BUNDLE_ID=… ruby scripts/generate_project.rb`.

## Layout

```
ReflexWhoop/
  App/        composition root (AppContainer), app entry, tabs, onboarding and settings keys
  Auth/       WHOOP OAuth2, Keychain token store
  Api/        WHOOP v2 models, client, rate limiter
  Ble/        band connection, envelope framing, opcode allowlist, decoders, recorder
  Ingest/     append-only inbox and the API/BLE normalizers
  Store/      GRDB database, migrations, DAO, time-series chunk codec and store
  Sync/       sync engine, staleness policy, background refresh, source status
  Analysis/   engines (baselines, anomalies, correlations, readiness) and screen read models
  Export/     CSV + SQLite snapshot + raw payload export
  UI/         DesignSystem/ plus one folder per tab: Today, Trends, Metrics, Band, Archive, Onboarding
ReflexWhoopTests/   XCTest, Fixtures/*.json (synthetic)
mcp-server/         read-only MCP server and Parquet converter
scripts/            generate_project.rb
```

## Rules that must never break

These protect a real person's band, history and credentials. Tests enforce several of
them; none may be relaxed to make a change easier.

1. **Bluetooth is read-only and live-stream only.**
   - Every outgoing command goes through `OpcodeAllowlist.assertAllowed`.
   - Never make `0x16`, `0x17`, `0x21`, `0x14`, `0x9A`, `0x1D` or `0x0A` sendable,
     not even behind a flag. They appear only in `Ble.ForbiddenOpcode`, for the test.
   - Never ACK a `0x2F` or `0x31` packet.
   - No write path to any band setting, alarm or clock.
   - Don't change the allowlist, `BandConnection`'s command path or
     `OpcodeAllowlistTests` without the maintainer's explicit sign-off.
2. **The archive is sacred.**
   - Never edit or reorder a registered migration; add a new one.
   - Never set `eraseDatabaseOnSchemaChange`.
   - Never delete from `ingest_inbox` or the normalized tables.
   - Derived tables are recomputable; history is not.
3. **Inbox first.** Any new source writes raw bytes to `ingest_inbox` before anything
   decodes them.
4. **Never fabricate.**
   - A missing input is `NULL` with a reason, never `0` or an interpolation.
   - Only decode a band field once captured frames confirm it, and record its
     confidence in `PROTOCOL-GEN5.md`.
   - Charts break lines at gaps.
5. **Analysis reads the neutral layer.** No new read of a WHOOP-shaped table
   (`cycles`, `recoveries`, `sleeps`, …) from `Analysis/`; widen the neutral layer
   instead ([contract](docs/ARCHITECTURE.md#the-source-neutral-contract)).
6. **No secrets or personal data in git.**
   - WHOOP client ID, secret and tokens live only in the Keychain.
   - `.secrets.local.json` is gitignored.
   - Never commit a database copied off a device, an export, a screenshot of real
     data, device or simulator identifiers, or a real name or email.
   - Fixtures are synthetic.
7. **Readiness and sleep debt appear on no screen** until the conditions in
   [DECISIONS](docs/DECISIONS.md#readiness-hidden-until-sleep-debt-is-rebuilt) hold.

## Conventions

**Swift and structure**
- Swift 5 language mode, iOS 26 deployment target, iPhone only, SwiftUI. UIKit only
  where SwiftUI has no API (web-auth presentation, the serif navigation-bar title).
- One type per file. Subviews are their own `View` structs in their own files. Button
  actions are methods, not inline closures with logic.
- Folders are by feature. `Analysis/`, `Store/`, `Ingest/`, `Sync/`, `Api/`, `Auth/`
  and `Export/` never import SwiftUI, so their logic tests without touching views.
- Match the surrounding code: doc comments explain *why*, at the density of the file
  you're in.

**Data**
- Views hold no SQL and no arithmetic. Add or extend a read model in `Analysis/` that
  returns a value type, and test it against a real on-disk database
  (`TestSupport.makeDatabase()`).
- Inside the app module, GRDB's connection type is always spelled `GRDB.Database`
  ([why](docs/DECISIONS.md#database-vs-grdbdatabase)).
- Day keys are UTC cycle-start dates (`RecordDAO.dayString`). Never format a key for
  display; show dates from `DayDates`.
- Temperatures are stored, exported and computed in Celsius. Convert only for display,
  through `Metric` and `TemperatureUnit` with `@Environment(\.temperatureUnit)`.
- Normal ranges and the unusual threshold come from `AnomalyEngine`'s constants, never
  a local copy.

**UI**
- Colours come from the asset catalog's generated symbols (`Color(.champagne)`); no
  hex or RGB literals in Swift. Every coloured state also carries a word.
- Text uses text styles and follows Dynamic Type; check layouts at the largest sizes.
  Charts get VoiceOver descriptions.
- Numbers use `FormatStyle` (see `FormatStyle+Readings.swift`), never
  `String(format:)`, which is only for hex byte dumps.
- Copy follows [DESIGN-SYSTEM.md](docs/DESIGN-SYSTEM.md#copy-rules): plain words, no
  protocol terms outside Signal details, missing data says why.

## Workflow

- **Tests first for logic.** Write the failing XCTest, then the code. All tests must
  pass before a commit; existing warnings in `ApiNormalizerTests` and
  `BleNormalizerTests` predate current work.
- **Verify UI in the Simulator.** Run the app, look at every screen the change
  touches, and check it at a large Dynamic Type size. A UI change isn't done because it
  compiles.
- **Keep docs true in the same change.** A non-obvious choice gets a
  `DECISIONS.md` entry; a structural change updates `ARCHITECTURE.md`; any new band
  finding goes into `PROTOCOL-GEN5.md` with its confidence and evidence. Don't create
  new plan or spec files in `docs/`.
- **Commits:** a plain-English imperative subject that says what changed for the user
  or the codebase ("Show skin temperature as its change from normal, in Celsius or
  Fahrenheit"). No type prefixes.

## Gotchas

- `PRAGMA auto_vacuum` must stay outside `prepareDatabase`; it fails on read-only pool
  connections, intermittently.
- `DatabasePool` needs a file; tests use temp files, not `:memory:`.
- Device builds need an Apple ID signed into Xcode. "No Accounts" or "login details
  were rejected" means re-adding the account in Xcode → Settings → Accounts.
- A free Apple ID build expires after 7 days. Reinstalling loses no data.
- Bluetooth doesn't work in the Simulator. Band screens there show their unavailable
  states; decoding is tested with captured frames in `FramingTests` and
  `RealtimeHRDecoderTests`.
