# ADR-001: What this app is when the WHOOP subscription ends

**Status:** Accepted — P0 through P3 implemented 2026-09-13
**Date:** 2026-09-13
**Deciders:** Jayanth (sole owner/operator)
**Supersedes:** nothing. Complements `docs/design.md` (the approved plan) and
`docs/DECISIONS.md` (the running implementation log).

---

## Context

`docs/design.md` opens by framing this project as a fix for WHOOP's closed app:
"no raw export, no history you own, no baselines you control." That framing is
correct about the *symptom* and wrong about the *dependency*. As built today,
every durable thing this app owns is leased:

| Asset | Who controls it | What happens if the membership lapses |
|---|---|---|
| Cycles / recovery / sleep / workouts | WHOOP cloud | No new records. Backfill stops. |
| Recovery %, strain, sleep stages | WHOOP cloud (computed there) | Gone. Not derivable on-device — `design.md`: "BLE gives no scores." |
| The band as a sensor | WHOOP (subscription-gated hardware) | Degrades. The strap is the loss-leader; the membership is the product. |
| Live BLE stream | The band, while a session runs | Only what we can decode. Today: heart rate. |
| The local archive | **Us** | Survives — *if* the schema doesn't wipe it (see S1 below). |

So the honest position, stated plainly because the alternative is expensive
self-deception: **you cannot engineer independence from WHOOP while the sensor
on your wrist is a WHOOP.** No amount of BLE reverse-engineering changes that.
The band holds signal, not scores, and the band itself stops being useful
hardware without the membership behind it.

What *is* engineerable is the difference between these two outcomes on the day
the subscription ends:

- **Today's outcome:** the app throws `ClientError.http` on every sync, shows an
  error, and becomes a read-only viewer of whatever happened to be in SQLite —
  with no defined behavior, no user-facing explanation, and no guarantee the
  history is still there (S1).
- **The outcome worth building:** the app keeps working. It says "WHOOP source
  is inactive; archive spans 2025-07-01 → 2026-09-13, 438 days, complete." Every
  baseline, trend, correlation, and export still runs, because they were never
  reading WHOOP-shaped data in the first place. A new sensor — a chest strap, a
  future band, anything that can produce timestamped samples — becomes a new
  adapter, not a rewrite.

The second outcome is not more work than the first *if decided now*. It becomes
progressively more expensive with every analysis query written against a
WHOOP-shaped column.

### The audit that prompted this

A grounded pass over the codebase (6,213 SLOC app, 1,280 SLOC tests, 99 tests
passing, zero TODOs — the code that exists is in good shape) found the following.
Severity is about *consequence*, not effort.

**S1 — Live data-loss hazard. `Store/Migrations/Migrator.swift:13`**

```swift
#if DEBUG
// Must never be enabled in a release build — it would delete a real user's history.
migrator.eraseDatabaseOnSchemaChange = true
#endif
```

The comment is right and the guard is useless. Every install that has ever
reached the device is a Debug build (`Build/Products/Debug-iphoneos/`, free
Apple ID, no Release configuration has ever been built or validated). The
"development only" wipe is therefore **armed in production, because production
is a development build.** The next migration whose hash doesn't match silently
destroys every record the app has ever collected. This is the single highest-
consequence defect in the repo and it contradicts the project's stated first
principle — retention: keep everything forever.

**S2 — The BLE pipeline terminates in the inbox. Nothing downstream exists.**

`SpikeRecorder` writes raw notification blobs to `ingest_inbox` and stops there.
Tracing every consumer:

- `ChunkStore` / `ChunkCodec` (146 SLOC, Phase 1) — **zero callers** anywhere in
  the app. Dead code.
- `ts_chunk`, `ts_rollup_minute` — written only from inside that dead code.
- `session_metrics` — declared in the schema, **never written by anything**.
- `mcp-server/server.py:193` `hrv_session()` LEFT JOINs `session_metrics`, so it
  returns a row of `NULL`s for rMSSD, SDNN, pNN50, DFA-α1, respiratory rate, and
  signal quality — for every session, always. The tool is wired to a table no
  code populates.

Net effect: **no BLE datum is queryable by anything.** Not by the app, not by
Trends, not by the MCP server, not by an export consumer. Even the one confirmed
decode — realtime heart rate, validated across three real worn sessions — is
rendered to a SwiftUI label and then discarded. The inbox-first discipline was
the right call and it worked; what was never built is the second half, the
normalizer that turns those bytes into rows.

This is the largest gap between "what the design doc describes" and "what runs,"
and it is almost certainly the source of the felt sense that the BLE data is
"not complete or sufficient." The channel coverage is a real and separate
limitation (below), but even the channel we *did* solve produces nothing
durable.

**S3 — No defined behavior for subscription lapse or entitlement loss.**

`WhoopClient.request` maps `401 → forceRefresh → retry once`, `429 → backoff`,
`5xx → backoff`, and everything else to a generic `ClientError.http(status:
body:)`. A lapsed membership — whatever it returns, 403 or 200-with-empty-pages —
is indistinguishable from a transient failure. There is no archive mode, no
"source inactive" state, and no test covering it. The app has never been run
against an account in this state, so its behavior there is literally unknown.

**S4 — No app icon.** `Resources/Assets.xcassets/AppIcon.appiconset/` contains a
`Contents.json` declaring a 1024×1024 universal slot and **no image file**. The
app installs with the iOS default placeholder.

**S5 — The Release configuration has never been built.** Every `#if DEBUG` guard
in the codebase is therefore untested in the configuration it exists to protect.
S1 is the first casualty of this; it will not be the last.

**S6 — Protocol drift has no detector.** `design.md` already names the risk ("a
firmware update can break the decoder overnight") and the inbox correctly
preserves the bytes. But nothing *notices*. If a firmware update moves the HR
byte from `inner[8]`, the app will keep reporting a plausible-looking number
from whatever now occupies that offset, indefinitely, with no signal that it is
wrong. There is no canary, no envelope-version assertion, no decode-confidence
metric persisted anywhere.

**S7 — `schema_meta` declared, never written.** No schema or algorithm version is
recorded in the database itself, so a snapshot's provenance can't be verified
against the code that produced it. (Partially mitigated: `Exporter` writes algo
versions into `manifest.json`, but the database alone is not self-describing.)

### What is *not* wrong

Worth stating so effort goes to the right places. The envelope reverse-
engineering is genuinely rigorous and confirmed against thousands of real frames.
`OpcodeAllowlist` is a correct structural safety mechanism, not a convention.
The inbox-first ingestion discipline is exactly right and has already paid for
itself twice (a wrong envelope hypothesis cost zero data; a wrong opcode-echo
theory was caught and retracted). The analysis layer — baselines, z-scores,
Benjamini-Hochberg-corrected correlations, the explicitly-not-WHOOP readiness
composite — is real statistics, correctly implemented, with 99 passing tests.
None of that needs revisiting. The problem is the *shape* of the dependency and
one unfinished pipeline, not the quality of what was built.

---

## Decision

**Reposition the system from "a WHOOP client" to "a personal physiology archive
with pluggable sources," and make archive integrity the top-priority invariant —
ahead of feature work, ahead of further BLE reverse-engineering.**

Concretely, three commitments:

1. **The archive is sacred.** No code path may destroy collected history. The
   schema becomes append-and-migrate-only in *every* build configuration, and
   the database becomes self-describing.
2. **Analysis reads a source-neutral layer, never a source-shaped one.** WHOOP
   API and band BLE become two adapters writing to the same normalized contract.
   Adding a third source must not require touching `BaselineEngine`,
   `CorrelationEngine`, `AnomalyEngine`, or any UI.
3. **Every source can be absent.** "WHOOP inactive" and "no band paired" are
   first-class, displayed, tested states — not error paths.

---

## Options Considered

### Option A: Status quo — WHOOP-coupled mirror

Keep the current coupling. Finish features as scoped in `design.md`.

| Dimension | Assessment |
|---|---|
| Complexity | Low — no restructuring |
| Cost | Zero now, total loss later |
| Scalability | N/A (single user) |
| Longevity | **Ends with the subscription** |

**Pros:** No work. Everything already written stays as-is.
**Cons:** The app's entire value terminates on a billing event outside your
control. The archive remains exposed to S1. Every additional analysis query
written against WHOOP-shaped columns raises the future cost of decoupling.

### Option B: Chase BLE autonomy

Attempt to make the band a standalone sensor: map r22/R21, and (implicitly)
reconsider historical flash drain to obtain overnight data without the cloud.

| Dimension | Assessment |
|---|---|
| Complexity | Very high — undocumented protocol, no layout hypothesis exists |
| Cost | Unbounded; 6 sessions invested, zero r22 frames captured |
| Longevity | Still zero — the band is subscription-gated hardware |
| Safety | **Requires breaching the project's own non-negotiable safety rail** |

**Pros:** Would yield the richest raw signal if it worked.
**Cons:** Does not solve the stated problem *even on success* — a band without a
membership is not a functioning sensor. Historical drain is permanently
forbidden by `design.md` and by every safety decision made in this project;
reopening it to chase autonomy would trade a certain, verified safety property
for a speculative benefit. The r22 blocker (`SENSORS: No active sources`) is
evidence of an unmet precondition nobody has identified across six sessions.

**Rejected.** Not because the reverse-engineering is unworthy — it should
continue opportunistically — but because it is not a strategy for longevity.

### Option C: Source-agnostic archive *(recommended)*

Normalize at a source-neutral boundary. WHOOP API and BLE become adapters.
Analysis and UI read only the neutral layer. Archive integrity is enforced
structurally. Source absence is a designed state.

| Dimension | Assessment |
|---|---|
| Complexity | Medium — mostly a boundary discipline, not a rewrite |
| Cost | Bounded; the normalized layer already exists and is already mostly neutral |
| Scalability | Adding source N+1 is an adapter, not a migration |
| Longevity | **Survives the subscription; survives the device; survives WHOOP** |

**Pros:** The 438 days already collected keep their full analytical value
forever. Trends, baselines, correlations, readiness, and the MCP server all keep
working with zero live sources. A future sensor plugs in without touching
analysis. Fixes S1/S2/S3 as a side effect of doing it properly.
**Cons:** Requires finishing the BLE normalizer that was skipped (S2), which is
real work. Requires defining the neutral contract carefully now, when the only
two sources are known — some guessing about what a third source needs.

### Option D: Rebuild on HealthKit as the neutral layer

Let Apple own the storage/normalization contract; write WHOOP data into
HealthKit and read it back.

**Rejected — structurally impossible here.** `design.md:217` is explicit: a free
Apple ID Personal Team grants no entitlement-backed capabilities, and HealthKit
is entitlement-gated. Named only so it is not re-proposed.

---

## Trade-off Analysis

The decisive question is not "which architecture is nicer" but **what is the
cost of being wrong in each direction.**

Choosing A and being wrong (subscription ends, or WHOOP deprecates API v2, or a
firmware update breaks BLE) costs the entire project. Choosing C and being wrong
(the subscription never lapses, no second sensor ever appears) costs a
normalizer that needed writing anyway — S2 is a gap under *every* option,
because without it the BLE work produces nothing queryable no matter what.

That asymmetry decides it. Option C's "wasted" work in the worst case is work
Option A also required.

On sequencing: S1 is not a trade-off at all. A latent wipe of irreplaceable
personal history — data that cannot be re-collected, because WHOOP's API
backfill depends on the very subscription this ADR is about — is not acceptable
in any configuration, under any deadline. It is fixed first, independent of
whether this ADR is accepted.

The one genuine tension is **neutral-layer design risk**: defining a source-
agnostic schema against a sample size of two sources invites over-abstraction.
Mitigation: the contract is derived from what analysis *actually reads today*
(`daily_metrics` columns and the time-series sample shape), not from imagined
future sensors. If a third source doesn't fit, it gets a migration — which is
the normal cost of learning, and is cheap once S1 makes migrations safe.

---

## Consequences

**Becomes easier**
- Adding any future data source — no analysis or UI changes.
- Reasoning about correctness: analysis has one input contract, not two.
- Honest UI: "WHOOP inactive, archive complete through <date>" instead of a
  stack trace.
- BLE decode work finally produces durable, queryable, exportable rows — which
  also means the MCP server can answer questions about live sessions.

**Becomes harder**
- Two hops instead of one for API data (adapter → neutral → analysis). Slightly
  more indirection in a codebase that is currently pleasantly direct.
- The BLE normalizer must decide what to do with *undecoded* channels. Proposed
  answer: the inbox keeps the bytes forever (unchanged); the normalizer emits
  rows only for confirmed decodes. Absent input yields "unavailable," never zero
  — consistent with `design.md`.

**Needs revisiting**
- If WHOOP ever ships a real export or a webhook API, the adapter changes and
  nothing else does — which is the point.
- The neutral contract should be re-examined the first time a third source is
  actually attempted, not speculatively before then.

---

## Action Items

Ordered by consequence, not effort. P0 items are hazards; P1 is the missing
product; P2+ implements this ADR.

**P0 — do immediately, independent of this ADR's acceptance**
1. [x] **S1:** Removed `eraseDatabaseOnSchemaChange` in all configurations. An
       edited migration now fails to open the database instead of resetting it.
       (`Store/Migrations/Migrator.swift`)
2. [~] **S1 follow-up:** Not implemented, and deliberately dropped. With the
       wipe gone, GRDB already refuses to proceed on a migration mismatch —
       a before/after record-count assertion would be a second guard against a
       failure mode the first one now makes impossible.
3. [x] **S4:** App icon shipped (`AppIcon.appiconset/icon-1024.png`), plus the
       `AccentColor` the asset catalog had been warning about.

**P1 — the missing half of Phase 4**
4. [x] **S2:** `Ingest/BleNormalizer.swift` — inbox → reassemble → decode
       confirmed fields → `ChunkStore`. Runs automatically when a session
       stops. Works a whole session per pass (not a fixed row batch) because
       `ChunkStore` overwrites buckets rather than merging, which would
       otherwise drop samples from a session split across two passes.
5. [x] **S2:** `session_metrics` populated with the HR summary, decode
       coverage, and `signal_quality`. HRV columns stay `NULL` — no RR channel
       exists — and both the MCP tool docstring and the schema comment now say
       so explicitly instead of leaving an unexplained void. Added
       `ble_sessions` and `ble_heart_rate` MCP tools.
6. [x] Backfill path shipped as `BleNormalizer.replay` + a "Re-derive BLE time
       series" button in the Data tab. Re-derives every session from the inbox
       bytes; run after any decoder improvement.

**P2 — implement the decision**
7. [x] **S3:** `Sync/SourceStatus.swift` — `SourceState` with `active` /
       `notConfigured` / `unauthorized` / `inactive` / `unreachable`, surfaced
       in a Settings "Sources" section. HTTP 403 maps to `inactive` via a new
       `sync_log.error_kind` column, distinctly from transient failures.
8. [x] **S3:** Archive mode. Today no longer blanks out when signed out if the
       archive holds data — it shows the analysis with a banner naming the
       source state and the archive's span.
9. [x] `docs/NEUTRAL-CONTRACT.md`. Audit result: the core path
       (baselines/anomalies/readiness) is already clean; `CorrelationEngine`
       and `AnalysisQueries` have two grandfathered reads of WHOOP-shaped
       tables, documented with the reason they are not being fixed yet.

**P3 — long-term support**
10. [x] **S5:** Release configuration built and validated for the first time.
        It surfaced three warnings (an unused `try?`, a Swift 6
        actor-isolation error-in-waiting, the missing accent color), all fixed.
11. [x] **S6:** Decode canary persisted per session as `signal_quality` plus
        `decoded` / `unmapped` / `corrupt` frame counts, exposed through the
        `ble_sessions` MCP tool. Firmware drift shows up as that ratio
        collapsing while frames keep arriving.
12. [x] **S7:** `Migrator.stampMeta` writes schema and decoder versions to
        `schema_meta` after every migration.

**Still outstanding**

- The canary is *recorded* but not *alarmed on* — nothing proactively warns
  when `signal_quality` drops. Deferred deliberately: with one decoder and no
  baseline for what normal drift looks like, a threshold now would be guessed.
  Revisit once a few more sessions establish the normal range.

**Explicitly deferred (not abandoned)**
- r22 / R21 / r26 mapping. Opportunistic only: attempt when a session happens to
  produce frames, per the existing `PacketTypeCounts` diagnostic. No further
  sessions should be *scheduled* around it until an unmet precondition is
  identified, and no schedule should depend on it succeeding.
