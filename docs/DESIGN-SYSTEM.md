# Design system: Onyx

Black and champagne, gem tones for data. iPhone only, dark only
(`.preferredColorScheme(.dark)`), iOS 26. Components live in `UI/DesignSystem/`;
colours are asset-catalog colour sets with generated Swift symbols
(`Color(.champagne)`, `.sunstone`, …).

## Colour

| Token | Value | Use |
|---|---|---|
| `onyx` | `#000000` | screen background |
| `surface` | `#121110` | list rows, cards |
| `surfaceRaised` | `#1A1917` | sheets, selected segment |
| `ivory` | `#F1ECE3` | primary text; secondary and tertiary use SwiftUI's hierarchical styles, not manual opacity |
| `champagne` (`AccentColor`) | `#D3BE99` | brand: tint, primary buttons, selected tab, toggles |
| `onChampagne` | `#15120D` | text on champagne |
| `jade` | `#71C69A` | high recovery, success |
| `amber` | `#F1BF5B` | moderate recovery |
| `garnet` | `#DB6D60` | low recovery, destructive |
| `sunstone` | `#F18D57` | unusual readings, warnings, membership ended |
| `roseQuartz` | `#E28DAE` | heart rate from the band |
| `sleepREM` / `sleepLight` / `sleepDeep` | `#86CADF` / `#658DC9` / `#555594` | sleep stages; awake is ivory at tertiary |

Amber stays distinct from champagne through chroma. Unusual readings use sunstone so
amber keeps one meaning. **Colour is never the only signal:** every coloured state
also carries a word.

Ivory is the root foreground style, which also replaces the grey SwiftUI gives
footers, labeled values and empty-state descriptions by default. `SectionFooter`,
`SecondaryValueLabeledContentStyle` and empty states set `.secondary` explicitly.

## Type

- **Display:** New York (`Font.display`, `.fontDesign(.serif)`) for large titles, hero
  numerals and onboarding headlines. Large navigation titles get the serif through
  `NavigationBarStyle`, since SwiftUI can't set title fonts.
- **Everything else:** SF Pro text styles, so all text follows Dynamic Type.
- **Hero numerals:** light serif, scaled with `@ScaledMetric(relativeTo: .largeTitle)`,
  proportional figures (tabular figures spread a light serif too wide at hero size).
- **Section headers:** footnote semibold, uppercase, tracked.

## Components

| Component | What it shows |
|---|---|
| `RangeStrip` | a track, the normal band (60-day mean ± 1 SD) and a dot for the value; the dot turns sunstone at \|z\| ≥ 2, the same threshold as `AnomalyEngine`. No dot without a reading. |
| `RecoveryZones` | 0–100 split at WHOOP's edges (0–33, 34–66, 67–100); only the current zone is coloured, with a marker and a bracket for the usual range |
| `StrainScale` | WHOOP's 0–21 scale with a marker |
| `SleepStageBar` | stage totals only; WHOOP doesn't provide the order, so none is drawn |
| `HeartRateChart`, `MetricHistoryChart` | Swift Charts on real time; lines break where readings stop (`GappedLineMarks`) and the normal band sits behind (`NormalBandMarks`) |
| `Sparkline` | the range chosen on Trends, the normal band, the last point emphasised |
| `MetricValueText`, `HeroValue` | a formatted value with its unit set smaller; a missing value is a dash read as "No reading" |
| `PrimaryButtonStyle` | champagne capsule, `onChampagne` label, at least 52 pt tall |
| `SectionHeader`, `SectionFooter`, `StatusLabel`, `InlineMessage` | headers, footers, a dot plus a word, inline errors |

Charts carry VoiceOver descriptions (`MetricHistoryChartDescriptor`); range strips
read the value, the range and the status.

## Screens

| Tab | Contents | Pushes to |
|---|---|---|
| **Today** | recovery hero (number, band, verdict, zones), strain, last night's sleep, overnight vitals against their normal, sync line. With no WHOOP scores it shows today's heart rate from the band instead of presenting an old day as today. | metric detail |
| **Trends** | 30 days / 90 days / 1 year / all; a sparkline row per metric; Patterns; Unusual days | metric detail, Patterns, Unusual days |
| **Band** | live heart rate and the last 20 minutes, Keep recording, this session, recent recordings, a read-only note; states for idle, searching, Bluetooth off, permission denied | recording detail, all recordings, Signal details |
| **Archive** | days held, date span, recordings, size on disk; WHOOP account and band sources; Export a copy; Rebuild heart-rate history; temperature units; About | WHOOP account, export sheet, About |

**First run** is shown only when onboarding isn't complete, the archive is empty and
no WHOOP account exists: Welcome → Choose sources → Bluetooth primer (turns on Keep
recording, which triggers the system prompt) → Connect WHOOP → first sync. Any source
can be skipped.

## Copy rules

- Plain words from the user's side of the screen. Protocol terms only on Signal
  details; no file or doc references anywhere in the UI.
- Missing data says why: "No reading that night", "Not enough history yet". Heart rate
  out of range explains that the band isn't recorded while it's away, because the app
  never reads the band's stored history.
- Recovery verdicts: high "Well recovered. A good day to train hard."; moderate
  "Moderate recovery. Train, but keep something in reserve."; low "Low recovery. Keep
  today easy." A day with an illness flag always says to keep it easy.
- Strain: under 10 light, 10–13.9 moderate, 14–17.9 high, 18 and over all out. Today's
  strain reads "so far" while its cycle is open.
- Skin temperature leads with its change from normal; temperatures follow the
  Temperature setting (Automatic, Celsius, Fahrenheit).
- Patterns never states a direction for a weak result, and shows how many more days
  each predictor needs.
- Readiness and sleep debt appear nowhere
  ([DECISIONS](DECISIONS.md#readiness-hidden-until-sleep-debt-is-rebuilt)).
- **About** explains how scores are worked out (recovery, strain and sleep come from
  WHOOP; "your normal" is the previous 60 days ± 1 SD; unusual is 2 SD or more) and
  what the app never does (change anything on the band, read its stored history,
  delete collected data).

## App icon

"Your normal" in champagne: three 1024 px PNGs in `AppIcon.appiconset` for the
default, dark and tinted Home Screen appearances. The default image has no alpha.

## Errors

Every query failure shows a quiet inline message and leaves the screen usable; nothing
falls back to zero. Sign-in, sync, export and rebuild failures appear beside the action
that caused them, and export and rebuild disable their buttons while running.
