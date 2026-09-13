# Onyx redesign — design spec

Date: 2026-09-13 · Branch: `onyx-redesign` · Status: approved by the owner

## Why

The current UI (commit `a546609`) is a custom always-dark theme with hard-coded
colours, fixed font sizes, custom cards instead of lists, five tabs plus a settings
sheet, and a live screen that opens on protocol diagnostics. Scored against the Apple
HIG skill's rubric it is about 4/10.

The owner reviewed a full redesign (design canvas, rev 2) and decided:

1. **Black base, ultra-premium brand colours.** Onyx: true black, champagne as the
   brand metal, gem tones for data.
2. **Hide readiness until it is fixed.** Its sleep-debt input reads exactly
   7,668,000 ms on 55 of 69 days, which zeroes one of its four components.
3. **Icon: "Your normal", champagne gold**, with the tinted appearance for iOS's
   tinted Home Screen mode.

## Non-goals

- No change to ingestion, BLE protocol handling, the opcode allowlist, sync, or the
  database schema. The redesign reads the same tables. Safety rules (live-stream only,
  never ACK history, read-only band, never fabricate, the archive is sacred) are
  untouched.
- No light mode. The brand is black; the app stays `.preferredColorScheme(.dark)`.
- The sleep-debt fix itself is separate work. This spec only hides readiness.
- No iPad, widgets, or Live Activities.

## Platform

- **Deployment target: iOS 17 → iOS 26.** The app runs on one iPhone (iOS 27). Raising
  the floor removes every `#available` branch and fallback for Liquid Glass,
  `Tab`, and `navigationSubtitle`, at no cost.
- Swift 5 language mode (unchanged), SwiftUI, Swift Charts, GRDB.

## Visual system

### Colour (Onyx)

| Token | Value | Use |
|---|---|---|
| `background` | `#000000` | Screen ground |
| `surface` | `#121110` | List rows, cards |
| `surfaceRaised` | `#1A1917` | Sheets, selected segment |
| `ivory` | `#F1ECE3` | Primary text. Secondary and tertiary text use SwiftUI hierarchical styles derived from it, not manual opacity |
| `champagne` | `#D3BE99` | Brand: tint, primary buttons, selected tab, toggles |
| `onChampagne` | `#15120D` | Text on champagne |
| `jade` | `#71C69A` | Recovery high, success |
| `amber` | `#F1BF5B` | Recovery moderate |
| `garnet` | `#DB6D60` | Recovery low, destructive |
| `sunstone` | `#F18D57` | Unusual readings, warnings, membership ended |
| `roseQuartz` | `#E28DAE` | Heart rate from the band |
| `sleepREM` / `sleepLight` / `sleepDeep` | `#86CADF` / `#658DC9` / `#555594` | Sleep stages; awake is `ivory` at tertiary |

Recovery moderate is amber (owner's choice, canvas rev 2.2). It stays distinct from
champagne through chroma: 0.13 against 0.055. Unusual readings use sunstone so amber
keeps a single meaning. Every
colour-coded state also carries a word; colour is never the only signal.

### Type

- **Display:** New York (`.fontDesign(.serif)`) for large titles, hero numerals and
  onboarding headlines. Large titles use UIKit navigation-bar appearance with a serif
  descriptor, since SwiftUI can't set title fonts.
- **UI:** SF Pro text styles everywhere else, so text follows Dynamic Type.
- **Hero numerals:** serif light, sized with `@ScaledMetric(relativeTo: .largeTitle)`,
  proportional figures. Tabular figures spread a light serif numeral too far apart at
  hero size (canvas rev 2).
- **Section headers:** footnote semibold, uppercase, tracked.

### Components (all in `UI/DesignSystem/`)

- `RangeStrip`: the track, the normal band (mean ± 1 SD of the **60-day** baseline),
  and a dot for the value. The dot is sunstone when |z| ≥ 2, which matches
  `AnomalyEngine`'s single-metric threshold, so the strip and the anomalies table
  always agree. No dot when there is no reading. VoiceOver reads the value, the
  range, and the status.
- `RecoveryZones`: a 0–100 strip split at WHOOP's edges (0–33, 34–66, 67–100). Only
  the current zone is coloured, with a marker and a bracket for the usual range.
- `StrainScale`: 0–21 track with a marker.
- `SleepStageBar`: stage totals only. WHOOP doesn't provide the order, so none is drawn.
- `HeartRateChart` and `MetricHistoryChart` (Swift Charts): real time on the x axis,
  and lines break where readings are missing rather than drawing across gaps.
- `Sparkline`: the range selected on Trends (default 30 days), normal band, emphasised last point.
- `PrimaryButtonStyle`: champagne capsule, `onChampagne` label, at least 52 pt tall.
- `SectionHeader`, `StatusLabel` (dot plus a word), and `SourceRow`.

## Information architecture

Before: Today · Trends · Patterns · Live · Data, plus a Settings sheet.
After: **Today · Trends · Band · Archive**.

| Tab | Contents | Pushes to |
|---|---|---|
| Today | Recovery hero (number, band word, verdict sentence, zones), strain scale, last night's sleep, overnight vitals with range strips, sync line | Metric detail (any vital, recovery, strain, sleep performance) |
| Trends | 30D/90D/1Y/All picker, sparkline rows for each metric, a Patterns row, an Unusual days row | Metric detail, Patterns, Unusual days |
| Band | Live heart rate hero and last-20-minute chart, Keep recording toggle, this session's stats, recent recordings, Signal details, read-only note. Other states: idle, looking for band, Bluetooth off, permission denied | Recording detail, All recordings, Signal details |
| Archive | Days held, date span, recordings, readings and size on disk; the WHOOP account and Band sources; Export a copy; Rebuild heart-rate history; About | WHOOP account (connected / membership ended / not connected, with a credentials form), Export sheet, Rebuild confirmation, About |

**First run** is a full-screen flow shown only when onboarding hasn't been completed
**and** the archive is empty. Existing installs with data skip it and are marked
complete. Steps: Welcome → Choose sources → (Band chosen) Bluetooth primer, which
enables Keep recording and so triggers the system prompt → (WHOOP chosen) Connect
WHOOP → (connected) Bringing in your history → Today. Any source can be skipped.

### Rules the screens follow

- **Verdict** (Today hero): high "Well recovered. A good day to train hard.";
  moderate "Moderate recovery. Train, but keep something in reserve."; low
  "Low recovery. Keep today easy." If that day has an `illness_flag` anomaly, add
  "Several signals are off from your normal." Sleep debt is never quoted, since its
  input is suspect.
- **Strain bands** (WHOOP's 0–21 scale): under 10 light, 10–13.9 moderate, 14–17.9
  high, 18 and over all out. Today's cycle reads "so far".
- **About** (Archive) has two sections. *How scores are worked out*: recovery, strain
  and sleep come from WHOOP; "your normal" is your previous 60 days ± 1 SD; unusual
  means more than 2 SD away. *What the app never does*: change anything on the band,
  read the band's stored history, or delete collected data.

### Readiness

Removed from every screen. `ReadinessEngine` keeps computing it, so the data and the
MCP server are unaffected. `TrendMetric.readinessScore` and
`DailyMetricsRow.readinessScore` are deleted as dead UI code. A `DECISIONS.md` entry
records why and what restores it.

## Architecture

The current pattern stays: pure read functions in `Analysis/` return value types, and
views call them from `.task`. It extends to screen-shaped read models so views hold
no SQL and no arithmetic.

- `Analysis/Metric.swift`: `Metric` replaces `TrendMetric` with the eight visible
  metrics (recovery, strain, sleep performance, HRV, resting HR, breathing rate,
  skin temperature, blood oxygen). It carries label, unit, number formatting,
  baseline column (if any), and Trends section.
- `Analysis/NormalRange.swift`, `ReadingStatus.swift` (`within`, `above`, `below`,
  `unusuallyHigh`, `unusuallyLow`, `noReading`, `notEnoughHistory`, with a single
  `classify(_:against:)`), `RecoveryBand.swift` and `StrainBand.swift`. One type per
  file, pure Swift, no SwiftUI.
- `Analysis/TodayQueries.swift`: `TodaySnapshot` holds the latest day's metrics,
  each vital's 60-day range, latest sleep with its performance, that day's
  anomalies, and the last sync time.
- `Analysis/MetricHistory.swift`: points and per-day ranges for a metric since a day.
- `Analysis/RecordingQueries.swift`: `RecordingSummary` (id, start, end, minutes
  with readings, average/min/max HR, reading count) and `minuteSeries(sessionID)`
  from `ts_rollup_minute`.
- `Analysis/UnusualDays.swift`: anomalies grouped by day, each with the day's value
  and range.
- `Ble/HeartRateWindow.swift`: a bounded rolling buffer of `(Date, bpm)` covering the
  last 20 minutes, fed by `SpikeRecorder` and read by the live chart.
- `BandConnection.ConnectionState.unavailable(String)` becomes
  `unavailable(Unavailability)` (`poweredOff`, `unauthorized`, `unsupported`), so the
  UI branches on a case instead of matching strings.
- `App/Onboarding.swift`: completion flag in `UserDefaults`, plus the rule for when
  the flow is shown.

UI folders: `UI/DesignSystem`, `UI/Today`, `UI/Trends`, `UI/Band`, `UI/Archive`,
`UI/Onboarding`, and `UI/RootView.swift`. Deleted: `Theme.swift`, `TodayView`,
`TrendsView`, `InsightsView`, `LiveView`, `DataView`, `SettingsView`.

## Copy rules

Plain words, from the user's side of the screen. No protocol terms outside Signal
details, and no file or doc references anywhere in the UI. Missing data says why
("No reading that night", "Not enough history yet"). Out of range says heart rate
isn't recorded while the band is away, because the app never reads the band's stored
history. Correlations never state a direction when the result is weak.

## App icon

`AppIcon.appiconset` gets three 1024 px square PNGs: any, dark, and tinted
(luminosity `dark`, `tinted`), exported by the design session into
`design/icon-export/`. The default image has no alpha.

## Error handling

- Every query failure shows a quiet inline message on its screen. Nothing is shown as
  zero, and the screen stays usable.
- Sign-in, sync, export and rebuild failures surface the error text next to the
  action that caused it.
- Export and rebuild disable their buttons while running.

## Testing

- **Unit (XCTest, existing style):** `ReadingStatus.classify` boundaries (±1 and ±2
  SD, nil value, nil range), `RecoveryBand` and `StrainBand` edges, `Metric`
  formatting, `HeartRateWindow` eviction, and onboarding visibility rules.
- **Database (on-disk temp DB via `TestSupport`):** `TodayQueries` with and without
  baselines; `RecordingQueries` minutes-with-readings and series with gaps;
  `UnusualDays` grouping; confirming readiness is absent from every read model.
- **Build:** `xcodebuild test` on the iPhone 17 simulator (iOS 26.5) passes the existing 122 tests
  plus the new ones.
- **Visual:** every screen checked in the Simulator against a copy of the real device
  database, then built and installed on the iPhone.
- **Review:** simplify pass, code review, accessibility review.
