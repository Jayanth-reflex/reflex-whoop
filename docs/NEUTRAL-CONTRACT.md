# The source-neutral contract

Implements commitment 2 of [`ADR-001`](ADR-001-data-sovereignty.md): *analysis
reads a source-neutral layer, never a source-shaped one.*

This document names a boundary that mostly already existed by accident of good
layering. Writing it down turns it from a habit into a rule that can be checked.

## The rule

```
     SOURCES (adapters)          NEUTRAL LAYER           ANALYSIS + UI
  ┌──────────────────────┐   ┌────────────────────┐   ┌──────────────────┐
  │ WhoopClient          │   │ daily_metrics      │   │ BaselineEngine   │
  │   → ApiNormalizer    │──▶│   (one row/day)    │──▶│ AnomalyEngine    │
  │   → cycles/sleeps/…  │   │                    │   │ ReadinessEngine  │
  │                      │   │ ts_chunk           │   │ CorrelationEngine│
  │ BandConnection       │   │ ts_rollup_minute   │   │                  │
  │   → SpikeRecorder    │──▶│   (channel, ts,    │   │ Trends / Insights│
  │   → BleNormalizer    │   │    value)          │   │ MCP server       │
  └──────────────────────┘   │ session_metrics    │   └──────────────────┘
                             └────────────────────┘
```

**Anything left of the neutral layer may know what WHOOP is. Nothing right of
it may.**

A new source — a chest strap, a different band, a CSV import of someone else's
export — is an adapter that writes `daily_metrics` and/or `ts_chunk`. It
requires no change to any engine or any screen. That is the whole test of
whether this boundary is real.

## What the neutral layer is

### `daily_metrics` — one row per calendar day

Source-neutral by construction: physiological quantities with SI-ish units and
no vendor semantics. `recovery_score` and `day_strain` are the exceptions —
they are WHOOP's own computed scores, carried because they're useful, and any
analysis that depends on them must tolerate their absence (a non-WHOOP source
will leave them `NULL`).

`readiness_score` is **ours**, computed by `ReadinessEngine` from the neutral
columns. It is explicitly not WHOOP's recovery score and must never be derived
from one.

### `ts_chunk` / `ts_rollup_minute` — sampled channels

Keyed by `(channel, session_id, bucket)`. `channel` is a neutral name — `"hr"`,
not `"0x28"` or `"whoop_realtime_hr"`. `BleNormalizer.Channel` holds the
vocabulary. A second source producing heart rate writes `"hr"` too, and every
existing chart keeps working.

### `session_metrics` — per-recording-session derived values

Neutral in the same way: `hr_mean`, `rmssd_milli`, `signal_quality`. Nothing in
the column set implies a WHOOP band produced it.

## Current conformance

Verified by reading every `FROM` in `ReflexWhoop/Analysis/`:

| Component | Reads | Conforms |
|---|---|---|
| `BaselineEngine` | `daily_metrics`, `baselines` | ✅ |
| `AnomalyEngine` | `baselines`, `daily_metrics` | ✅ |
| `ReadinessEngine` | `daily_metrics` | ✅ |
| `CorrelationEngine` | `daily_metrics` — plus `sleeps`/`sleep_stage_summary` for predictors | ⚠️ see below |
| `AnalysisQueries` | `daily_metrics`, `anomalies`, `correlations` — plus `sleeps`, `sleep_need`, `recoveries`, `cycles` for detail views | ⚠️ see below |
| `DailyMetricsBuilder` | `cycles`, `recoveries`, `sleeps`, `sleep_stage_summary`, `sleep_need` | ✅ — it *is* the WHOOP adapter |

### The two known violations, and why they are tolerated for now

`CorrelationEngine` and `AnalysisQueries` reach past `daily_metrics` into the
WHOOP-shaped tables for things that layer doesn't carry: sleep-stage
percentages, sleep-need breakdowns, per-workout detail.

This is a real coupling, not a false positive. It is tolerated because:

1. It is **read-only and additive** — these are extra predictors and detail
   panels, not the core baseline/anomaly/readiness path, which is clean.
2. Fixing it properly means widening `daily_metrics` (or adding a neutral
   `daily_sleep_detail`), which is a schema decision better made when a second
   source actually exists and shows what the shared shape should be. Widening
   it now against a sample size of one source is how you get an abstraction
   that fits nothing.

**The rule for new code is unconditional even so: do not add a new read of a
WHOOP-shaped table from `Analysis/`.** If something is needed there, it goes
into the neutral layer first. The existing two are grandfathered debt with a
named reason, not a precedent.

## How to add a source

1. Write an adapter under `Api/` or `Ble/` that lands raw bytes in
   `ingest_inbox` (inbox-first is non-negotiable — see `IngestInbox`).
2. Write a normalizer that turns those bytes into `daily_metrics` rows and/or
   `ChunkStore.write(channel:…)` samples, emitting values only for fields it
   can actually decode. Absent input yields `NULL`, never `0`.
3. Add a `SourceState` case for it so it can be absent gracefully.
4. Change nothing in `Analysis/` or `UI/`. If you have to, the boundary leaked
   — fix the boundary instead.
