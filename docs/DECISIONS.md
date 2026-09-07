# Decisions log

Short record of choices that aren't obvious from the code, and why. See
`~/.claude/plans/design-a-a-whoop-kind-hinton.md` (or the copy at the bottom of this
repo's history) for the full design doc this project was built from.

## Storage location: Documents, not Application Support

`UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace` only exposes `Documents/`
in Files and over a Finder cable. A free Apple ID has no iCloud entitlement, so this
is the export path available — the database and exports live where they're reachable.

## `Database` vs `GRDB.Database` naming collision

Our own `Database` class (in `Store/Database.swift`) and GRDB's `Database` connection
type share a name. Inside `ReflexWhoop`'s own module, an unqualified `Database`
resolves to *our* type (module-local wins over imported), which is what call sites
like `AppContainer.database: Database` want. But anywhere GRDB's connection type is
meant — every `Migrator` helper, every DAO function, every `ChunkStore` function — the
parameter must be spelled `GRDB.Database` explicitly, and the same is true from the
test target (which has no "home module" advantage and gets a hard ambiguity error
instead of silently picking the wrong one). Get this wrong and the compiler error is
misleading ("value of type 'Database' has no member 'create'") rather than an ambiguity
complaint, because Swift resolved it to a real-but-wrong type.

## `PRAGMA auto_vacuum` set outside `prepareDatabase`

`Configuration.prepareDatabase` runs for every connection `DatabasePool` opens,
including its read-only reader connections. Most PRAGMAs (`synchronous`, `temp_store`,
`mmap_size`) are connection-local and safe there. `auto_vacuum` rewrites the database
header and fails with "attempt to write a readonly database" on a reader connection —
it's set once via an explicit `dbPool.write` block in `Database.init` instead. This
bug is intermittent by nature (it depends on which connection GRDB happens to open
first), which is exactly the kind of thing to get right in Phase 1 rather than have it
resurface as a flaky crash months into real use.

## Content-hash skip is per-DAO-call, not per-inbox-row

`RecordDAO.upsert` computes a hash over the fields that matter and skips the write if
unchanged. This is deliberately *not* keyed to inbox `seq` — the same inbox row is
never reprocessed twice (once decoded, `decoded_at` is set), but the same *record* can
arrive via two different inbox rows (today's sync and next week's 7-day lookback
re-fetch), and the hash comparison is what makes the second arrival a no-op.

## `ApiNormalizer.processPending` re-sweeps until stable

Inbox rows are processed in arrival order, which is usually also dependency order
(profile before body measurement) but isn't guaranteed within one sync batch. Rather
than only resolving a deferred row on the *next* call, one call re-sweeps (bounded to
5 rounds) while a round makes progress and rows remain deferred — see
`ApiNormalizerTests.testBodyMeasurementDefersUntilProfileExistsThenSelfHealsOnNextPass`
for the scenario this fixes.

## No xcodegen/tuist — hand-rolled `scripts/generate_project.rb`

Homebrew's prefix on this machine is owned by root (`/opt/homebrew` needs `sudo
chown`), which this environment can't do non-interactively. `gem install
--user-install xcodeproj` needs no sudo and provides everything needed to generate a
correct `.xcodeproj` from a plain Ruby script. Re-run `ruby scripts/generate_project.rb`
after adding or removing source files — it walks the directory tree fresh each time
rather than being hand-maintained.

## Day bucketing ignores `timezone_offset`

`RecordDAO.dayString(for:)` buckets by UTC calendar day, not the record's local day.
A record a few hours either side of local midnight can land on the "wrong" day
relative to WHOOP's own app. Acceptable for v1 trend/correlation work; would need
revisiting if exact day-boundary precision matters (e.g. sleep-debt accounting).

## `offline` scope isn't a Developer Dashboard checkbox

The WHOOP Developer Dashboard's app-creation form lists six scopes to tick
(`read:profile read:body_measurement read:cycles read:recovery read:sleep
read:workout`) with no `offline` toggle anywhere in the UI. `OAuthConfig.scopes`
requests it anyway, appended in the authorize URL's `scope` parameter — confirmed
against the real API that this works and a refresh token comes back, so `offline`
is a protocol-level modifier requested at auth time, not a per-app registration.

## Token exchange uses `client_secret_post`, not HTTP Basic auth

`WhoopAuth`'s token requests put `client_id`/`client_secret` in the URL-encoded
request body alongside `grant_type`, rather than an `Authorization: Basic` header.
WHOOP's docs don't specify which OAuth2 client-authentication method their token
endpoint expects; body params worked against the real API on the first live test
(see README's "Verification"). If a future WHOOP API change starts rejecting this,
switching to Basic auth in `WhoopAuth.postTokenRequest` is the fix to try first.

## Settings lives behind a toolbar icon, not a 6th tab

`RootView`'s `TabView` originally had six tabs (Today/Trends/Insights/Live/Data/
Settings). iOS collapses anything past 5 into an auto-generated "More" list — worse
UX on its own, and this specific case also turned out to be unreliable to drive via
simulator UI automation (tapping a row in the system-generated "More" list
intermittently failed to navigate, while every other tap in the app worked fine).
Moved Settings to a gear icon in Today's toolbar, opened as a sheet — a standard
iOS pattern for a low-frequency screen, and it fixed both problems at once.

## Free Apple ID: hardcoded `DEVELOPMENT_TEAM`, and Xcode's own session can expire

`scripts/generate_project.rb` sets `DEVELOPMENT_TEAM` to a specific Personal Team ID
rather than leaving it for Xcode to resolve interactively — needed for `xcodebuild`
to sign a device build non-interactively at all. Building under a different Apple ID
means changing that one line. Separately: Xcode's *own* stored login for an Apple ID
can silently expire ("Unable to log in with account ... The login details were
rejected") and needs a manual Xcode → Settings → Accounts → remove-and-re-add to
fix — this is unrelated to the WHOOP OAuth flow and can't be scripted, since it needs
the Apple ID password/2FA interactively.

## `stats.upserted` counts inbox pages, not individual records

`ApiNormalizer.processPending`'s `Stats.upserted` increments once per inbox row
(page) that produced at least one change, not once per normalized record inside
that page. A `sync_log` entry showing e.g. "14 requests, 13 upserted" after a
backfill that actually wrote 243 rows across cycles/recoveries/sleeps/workouts is
correct, not a bug — the per-table row counts are what to check for record-level
accuracy, `sync_log.records_upserted` is a coarser "did this batch do anything"
signal.

## `AppContainer.syncIfDueOnForeground()` checks `auth.isSignedIn()` directly

Not the cached `isSignedIn` published property. `RootView`'s own `.task` (which
calls `syncIfDueOnForeground`) and the outer `.task { await container.
refreshSignInState() }` attached in `ReflexWhoopApp` are two independent `.task`
modifiers with no ordering guarantee between them — reading the cached property
risked silently skipping the very first sync on a fresh launch if it happened to
run before `refreshSignInState()` set the flag. Caught by inspection while wiring
the foreground-sync trigger, before it shipped.

## Baseline windows exclude the day they're scoring

`BaselineEngine` computes a day's mean/stddev from the N days *strictly before* it,
never including the day itself, then z-scores that day's actual value against that
window. Including the target day would let an extreme value pull its own baseline
toward itself, muting exactly the deviation a baseline exists to catch.

## `ReadinessEngine`'s sleep-debt scoring uses a fixed 2-hour scale

Rather than each night's personalized `sleep_need.baseline_milli` (which would need
an extra join per day). A debt of 2+ hours zeroes out that component; less scales
linearly. Documented as a heuristic in the code, not presented as precise — revisit
if it feels wrong in practice once more real data accumulates.

## `CorrelationEngine` recomputes the entire history every run

Rather than incrementally updating correlations for only what changed. A personal
WHOOP history tops out at a few hundred days, so a full recompute is milliseconds —
cheap enough that getting incremental-update invalidation subtly wrong isn't worth
the risk it would introduce.
