# Decisions

Choices that aren't obvious from the code, and why. The larger decision to make the
archive source-neutral is [ADR-001](ADR-001-data-sovereignty.md); how the system fits
together is [ARCHITECTURE.md](ARCHITECTURE.md).

## Build and platform

### A Ruby generator instead of xcodegen or tuist

`scripts/generate_project.rb` builds `ReflexWhoop.xcodeproj` from the files on disk with
the `xcodeproj` gem, which installs with `gem install --user-install` and needs no
Homebrew or sudo. Re-run it after adding or removing a file; never hand-edit the
project. UUIDs are derived from the project's contents (two passes of
`predictabilize_uuids`), so regenerating an unchanged tree writes an identical file.

### Signing comes from a git-ignored xcconfig

`xcodebuild` can only sign a device build non-interactively with `DEVELOPMENT_TEAM`
set, but a team ID identifies one person's developer account and has no place in a
public repository. The generated project sets neither the team nor a literal bundle
ID. Both come from `Config/Signing.xcconfig`, applied at the project level, which
optionally includes `Config/Signing.local.xcconfig`: git-ignored, one line per
developer. Xcode and `xcodebuild` read it the same way, and regenerating the project
never disturbs it. Without it, Simulator builds and tests still work.

A fork also sets `REFLEXWHOOP_BUNDLE_ID` there, because a bundle ID can belong to
only one team.

Xcode's own stored Apple ID login can expire silently ("The login details were
rejected", or "No Accounts"). The fix is removing and re-adding the account in Xcode →
Settings → Accounts; it needs the password interactively and can't be scripted.

### Storage in Documents, not Application Support

`UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` expose only
`Documents/` in Files and over a Finder cable. A free Apple ID has no iCloud
entitlement, so this is the export path available.

## Database

### `Database` vs `GRDB.Database`

The app's `Database` class and GRDB's connection type share a name. Inside the app
module an unqualified `Database` resolves to the app's type, so every migration
helper, DAO and `ChunkStore` function must spell GRDB's as `GRDB.Database`; the test
target gets an ambiguity error instead. Get it wrong and the compiler reports
something misleading ("value of type 'Database' has no member 'create'").

### `PRAGMA auto_vacuum` is set outside `prepareDatabase`

`prepareDatabase` runs for every connection `DatabasePool` opens, including read-only
readers. `auto_vacuum` rewrites the header and fails on a reader with "attempt to
write a readonly database", intermittently, depending on which connection opens
first. It's set once in an explicit write in `Database.init`.

### The content-hash skip is per record, not per inbox row

An inbox row is never processed twice, but the same record can arrive in two rows
(today's sync and next week's 7-day lookback). `RecordDAO.upsert` hashes the fields
that matter and skips an unchanged record, which makes the lookback nearly free.

### `ApiNormalizer.processPending` re-sweeps until stable

Rows are processed in arrival order, which usually but not always matches dependency
order (profile before body measurement). One call re-sweeps, up to five rounds, while
a round makes progress and rows remain deferred.
`testBodyMeasurementDefersUntilProfileExistsThenSelfHealsOnNextPass` covers it.

### `sync_log.records_upserted` counts pages, not records

It increments once per inbox page that changed something. "14 requests, 13 upserted"
after a backfill that wrote 243 rows is correct; per-table counts are the
record-level check.

## WHOOP API

### `offline` isn't a Developer Dashboard checkbox

The dashboard lists six scopes and no `offline`. The app requests it in the authorize
URL anyway, and WHOOP returns a refresh token, so it's a request-time modifier rather
than a per-app registration.

### Token requests use `client_secret_post`

`WhoopAuth` sends `client_id` and `client_secret` in the form body rather than an
HTTP Basic header. WHOOP doesn't document which it expects; the body worked on the
first live test. If WHOOP starts rejecting it, switch `WhoopAuth.postTokenRequest` to
Basic auth first.

### Foreground sync checks `auth.isSignedIn()` directly

Not the cached `isSignedIn` property. The `.task` that syncs on foreground and the one
that refreshes sign-in state have no ordering guarantee, so reading the cached value
could skip the first sync after launch.

## Analysis

### A baseline excludes the day it scores

`BaselineEngine` uses the days strictly before the target day. Including it would let
an extreme value pull its own baseline toward itself and mute the deviation.

### Correlations recompute the whole history every run

A personal history is a few hundred days, so a full recompute takes milliseconds, and
it can't get incremental invalidation subtly wrong.

### Normal ranges use the 60-day window

Every range the app draws is the 60-day mean ± 1 SD, and "unusual" is |z| ≥ 2. Both
constants come from `AnomalyEngine`, so a reading can't look normal on one screen and
appear in Unusual days on another. `ReadingStatusTests` pins the link.

### A day flagged for possible illness is never a day to push

`RecoveryBand.verdict(illnessFlagged:)` says to keep today easy whenever an illness
flag was raised, whatever the recovery score.

### Readiness hidden until sleep debt is rebuilt

Readiness appears on no screen. `ReadinessEngine` still computes it and the MCP server
still exposes it, but one of its four inputs is wrong.

WHOOP's `sleep_needed.need_from_sleep_debt_milli` is the extra sleep WHOOP attributes
to debt, and WHOOP caps it: raw sleep pages return exactly 7,668,000 ms (2 h 7.8 min)
on 55 of 68 nights. `DailyMetricsBuilder` copies it into `daily_metrics.sleep_debt_milli`
as if it were debt owed, and `ReadinessEngine` zeroes the component at a fixed 2 h,
below the cap, so the component scores zero on every capped night. It is WHOOP's value
as sent, not an ingestion bug. Measured directly (need = baseline + strain + nap need,
against light + deep + REM sleep), the real seven-night deficit over the same period
is 12–21 h.

Restore readiness when all of these hold:

- Debt is the app's own rolling seven-night deficit, grouped by `cycle_id`.
- It is scored on an absolute scale: 0 h scores 100, 14 h or more scores 0.
- Nothing presents the capped WHOOP term as debt.
- A fixture with capped nights proves the component no longer saturates.

### Days are shown as the morning they belong to

`RecordDAO.dayString(for:)` keys a day by the UTC date its cycle started, ignoring
`timezone_offset`, and a cycle starts when its night's sleep does. For anyone who
falls asleep before midnight UTC (every night in India) that key is the evening
before the morning the scores belong to. The key stays, since every engine joins on
it; only what's shown changes:

- `DayDates` shows a day as the local date its main sleep ended, the same sleep
  `DailyMetricsBuilder` scores the day from. A day with no sleep keeps its key's date.
- Strain reads "so far" while the day's cycle has no end, not by comparing dates.
- "Last night" means a sleep that ended today; anything older is "Latest sleep".

### Skin temperature leads with its change from normal

WHOOP sends an absolute reading (33.9 °C), but the number varies far more between
people than night to night, so the WHOOP app shows the change from baseline. The app
leads with the difference from that day's 60-day mean, with the reading beside it. A
night without a normal range shows the reading alone rather than a difference made up
from too little history.

The Temperature setting in Archive is Automatic (the iPhone's temperature unit, which
can differ from its region), Celsius or Fahrenheit. Stored values, exports and every
calculation stay in Celsius; only display converts. A difference converts by
converting both ends, so Fahrenheit's 32° offset cancels.

## Band

### Recording from the band is one setting

Keep recording is the only way to record. On, `AppContainer` holds one app-lifetime
`SpikeRecorder` that reconnects by itself and survives backgrounding; off, there is no
recorder. The earlier one-off session did the same with less resilience, so it was
removed rather than kept as a second path. The Bluetooth permission prompt therefore
appears when someone turns recording on, never at launch.
