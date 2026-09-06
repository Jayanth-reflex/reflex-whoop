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
