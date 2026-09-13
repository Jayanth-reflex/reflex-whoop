# Onyx Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace ReflexWhoop's UI with the owner-approved Onyx design — four tabs, black and champagne with gem-toned data, New York display type, hidden readiness, and the "Your normal" icon — without touching ingestion, BLE safety, sync, or schema.

**Architecture:** Pure, tested read models in `Analysis/` return screen-shaped value types; SwiftUI views in feature folders load them in `.task` and hold no SQL or arithmetic. A small design system in `UI/DesignSystem/` supplies tokens and the custom data components; everything else is a standard iOS control.

**Tech Stack:** Swift 5 mode, SwiftUI (iOS 26), Swift Charts, GRDB 6, XCTest.

**Spec:** `docs/superpowers/specs/2026-09-13-onyx-redesign-design.md`

## Global Constraints

- Deployment target iOS 26.0; iPhone only; `.preferredColorScheme(.dark)`.
- Normal range = `NormalRange.windowDays` (= `AnomalyEngine.baselineWindow`, 60) mean ± 1 SD; unusual = |z| ≥ `AnomalyEngine.singleMetricThreshold` (2.0).
- Readiness appears on no screen. Sleep debt is quoted on no screen.
- Never render a missing value as zero; missing says why.
- No protocol terms or doc/file references in user-facing strings, except on Signal details (protocol terms only).
- BLE stays read-only, live-stream only; no change to `OpcodeAllowlist`, `BandConnection` command paths, sync, or migrations.
- One type per new Swift file; subviews are separate `View` structs in their own files; button actions are methods; no `String(format:)`, use `FormatStyle`.
- After adding or removing any Swift file: `ruby scripts/generate_project.rb`.
- Test command: `xcodebuild test -project ReflexWhoop.xcodeproj -scheme ReflexWhoop -destination 'id=43F27AD1-D2C1-4C3A-8514-0CA178C92F77' -derivedDataPath "$DD"` with `DD=/private/tmp/claude-501/-Users-jayanth-Desktop-resume-projects-deadhand-switch/b62aa479-f053-4eac-93ff-ab6e6a121cdd/scratchpad/dd-onyx`.
- Skills to load when a task starts: SwiftUI tasks → `swiftui-expert-skill` (latest-apis + topic refs) and `swiftui-pro` refs; HIG-facing tasks → `ios-hig-design`; concurrency changes → `swift-concurrency-pro`; all code → `superpowers:test-driven-development` where logic exists.

## File map

| Area | Create | Modify | Delete |
|---|---|---|---|
| Platform | — | `scripts/generate_project.rb` | — |
| Domain | `Analysis/Metric.swift`, `NormalRange.swift`, `ReadingStatus.swift`, `RecoveryBand.swift`, `StrainBand.swift`, `HistoryRange.swift`, `ContinuousRuns.swift` | `AnomalyEngine.swift` (expose window/threshold, kind enum), `AnalysisQueries.swift` (remove `TrendMetric`, readiness), `RecordDAO.swift` (`date(forDay:)`), `DailyMetricsBuilder.swift`, `CorrelationEngine.swift` (use shared day parsing) | — |
| Read models | `Analysis/TodaySnapshot.swift`, `MetricPoint.swift`, `MetricHistory.swift`, `HeartRateReading.swift`, `RecordingSummary.swift`, `RecordingQueries.swift`, `UnusualReading.swift`, `UnusualDay.swift`, `UnusualDays.swift` | `AnalysisQueries.swift` (`normalRanges`, sleep performance), `Store/Database.swift` (`path`, `onDiskByteCount`) | — |
| BLE | `Ble/HeartRateWindow.swift` | `Ble/BandConnection.swift` (`Unavailability`), `Ble/SpikeRecorder.swift` (window) | — |
| App | `App/Onboarding.swift`, `App/AppTab.swift` | `App/ReflexWhoopApp.swift` | — |
| Design system | `UI/DesignSystem/*` | `Resources/Assets.xcassets/AppIcon.appiconset`, `AccentColor.colorset` | `UI/Components/Theme.swift` |
| Screens | `UI/Today/*`, `UI/Metrics/*`, `UI/Trends/*`, `UI/Band/*`, `UI/Archive/*`, `UI/Onboarding/*` | `UI/RootView.swift` | `UI/TodayView.swift`, `TrendsView.swift`, `InsightsView.swift`, `LiveView.swift`, `DataView.swift`, `SettingsView.swift` |
| Docs | — | `docs/DECISIONS.md`, `docs/design.md` (UI section), `mcp-server/server.py` (docstring) | — |

---

### Task 1: Raise the deployment target to iOS 26

**Files:** Modify `scripts/generate_project.rb:19`

- [ ] **Step 1:** Change `DEPLOYMENT_TARGET = '17.0'` to `DEPLOYMENT_TARGET = '26.0'` and replace the comment above the constant with: `# iOS 26: the app runs on one iPhone (iOS 27); the floor removes every #available branch for Liquid Glass, Tab and navigationSubtitle.`
- [ ] **Step 2:** `ruby scripts/generate_project.rb`
- [ ] **Step 3:** Run the test command. Expected: `Executed 122 tests, with 0 failures`.
- [ ] **Step 4:** Commit `Raise deployment target to iOS 26`.

### Task 2: Domain types — metrics, ranges, status, bands, history ranges, runs

**Files:**
- Create: the seven `Analysis/` domain files above.
- Modify: `Analysis/AnomalyEngine.swift`, `Store/DAO/RecordDAO.swift`, `Analysis/DailyMetricsBuilder.swift`, `Analysis/CorrelationEngine.swift`
- Test: `ReflexWhoopTests/MetricTests.swift`, `ReadingStatusTests.swift`, `BandTests.swift`, `HistoryRangeTests.swift`, `ContinuousRunsTests.swift`, `RecordDAOTests.swift` (extend)

**Interfaces — Produces:**
```swift
enum Metric: String, CaseIterable, Identifiable, Hashable { case recovery, strain, sleepPerformance, heartRateVariability, restingHeartRate, breathingRate, skinTemperature, bloodOxygen
  enum Section: CaseIterable { case scores, overnight }
  var column: String; var label: String; var shortLabel: String; var unit: String; var fractionDigits: Int; var section: Section; var hasNormalRange: Bool
  func formatted(_ value: Double, locale: Locale = .current) -> String
  init?(column: String) }
struct NormalRange: Equatable { static let windowDays: Int; let mean: Double; let standardDeviation: Double; var lowerBound: Double; var upperBound: Double; func zScore(of: Double) -> Double? }
enum ReadingStatus: Equatable { case within, above, below, unusuallyHigh, unusuallyLow, noReading, notEnoughHistory
  static func classify(_ value: Double?, against range: NormalRange?) -> ReadingStatus; var isUnusual: Bool; var label: String }
enum RecoveryBand: Equatable { case low, moderate, high; init(score: Double); var label: String; var verdict: String; static let illnessNote: String }
enum StrainBand: Equatable { case light, moderate, high, allOut; static let scaleMaximum: Double; init(strain: Double); var label: String }
enum HistoryRange: String, CaseIterable, Identifiable { case thirtyDays, ninetyDays, year, all; var label: String; var days: Int?; func firstDay(endingOn: Date) -> String? }
enum ContinuousRuns { static func split<Sample>(_ samples: [Sample], maximumGap: TimeInterval, time: (Sample) -> Date) -> [[Sample]] }
enum AnomalyEngine { enum Kind: String { case illnessFlag = "illness_flag", singleMetricExcursion = "single_metric_excursion" }; static let singleMetricThreshold = 2.0; static let baselineWindow = 60 }
extension RecordDAO { static func date(forDay: String) -> Date? }
```

- [ ] **Step 1: Write failing tests.**

`ReflexWhoopTests/ReadingStatusTests.swift`
```swift
import XCTest
@testable import ReflexWhoop

final class ReadingStatusTests: XCTestCase {
    private let range = NormalRange(mean: 60, standardDeviation: 5)

    func testMissingValueIsNoReadingEvenWithARange() {
        XCTAssertEqual(ReadingStatus.classify(nil, against: range), .noReading)
    }

    func testValueWithoutRangeIsNotEnoughHistory() {
        XCTAssertEqual(ReadingStatus.classify(61, against: nil), .notEnoughHistory)
    }

    func testZeroSpreadCannotClassify() {
        XCTAssertEqual(ReadingStatus.classify(61, against: NormalRange(mean: 60, standardDeviation: 0)), .notEnoughHistory)
    }

    func testBoundaries() {
        XCTAssertEqual(ReadingStatus.classify(64.99, against: range), .within)
        XCTAssertEqual(ReadingStatus.classify(65, against: range), .above)
        XCTAssertEqual(ReadingStatus.classify(55, against: range), .below)
        XCTAssertEqual(ReadingStatus.classify(69.99, against: range), .above)
        XCTAssertEqual(ReadingStatus.classify(70, against: range), .unusuallyHigh)
        XCTAssertEqual(ReadingStatus.classify(50, against: range), .unusuallyLow)
    }

    /// The strip and the anomalies table must never disagree about "unusual".
    func testUnusualThresholdIsTheAnomalyEngines() {
        let atThreshold = range.mean + range.standardDeviation * AnomalyEngine.singleMetricThreshold
        XCTAssertTrue(ReadingStatus.classify(atThreshold, against: range).isUnusual)
        XCTAssertEqual(NormalRange.windowDays, AnomalyEngine.baselineWindow)
    }
}
```

`ReflexWhoopTests/BandTests.swift`
```swift
import XCTest
@testable import ReflexWhoop

final class BandTests: XCTestCase {
    func testRecoveryBandEdgesMatchWhoop() {
        XCTAssertEqual(RecoveryBand(score: 0), .low)
        XCTAssertEqual(RecoveryBand(score: 33), .low)
        XCTAssertEqual(RecoveryBand(score: 34), .moderate)
        XCTAssertEqual(RecoveryBand(score: 66), .moderate)
        XCTAssertEqual(RecoveryBand(score: 67), .high)
        XCTAssertEqual(RecoveryBand(score: 100), .high)
    }

    func testStrainBandEdges() {
        XCTAssertEqual(StrainBand(strain: 0.5), .light)
        XCTAssertEqual(StrainBand(strain: 9.99), .light)
        XCTAssertEqual(StrainBand(strain: 10), .moderate)
        XCTAssertEqual(StrainBand(strain: 14), .high)
        XCTAssertEqual(StrainBand(strain: 18), .allOut)
        XCTAssertEqual(StrainBand.scaleMaximum, 21)
    }

    func testVerdictNeverMentionsSleepDebt() {
        for band in [RecoveryBand.low, .moderate, .high] {
            XCTAssertFalse(band.verdict.localizedStandardContains("debt"))
        }
    }
}
```

`ReflexWhoopTests/MetricTests.swift`
```swift
import XCTest
@testable import ReflexWhoop

final class MetricTests: XCTestCase {
    private let posix = Locale(identifier: "en_US_POSIX")

    func testReadinessIsNotAMetric() {
        XCTAssertNil(Metric(column: "readiness_score"))
        XCTAssertFalse(Metric.allCases.map(\.column).contains("readiness_score"))
    }

    func testColumnRoundTrip() {
        for metric in Metric.allCases {
            XCTAssertEqual(Metric(column: metric.column), metric)
        }
    }

    func testNormalRangesExistExactlyForBaselinedMetrics() {
        let baselined = Set(Metric.allCases.filter(\.hasNormalRange).map(\.column))
        XCTAssertEqual(baselined, Set(BaselineEngine.metrics))
    }

    func testFormatting() {
        XCTAssertEqual(Metric.recovery.formatted(85.4, locale: posix), "85")
        XCTAssertEqual(Metric.strain.formatted(0.506, locale: posix), "0.5")
        XCTAssertEqual(Metric.breathingRate.formatted(13.16, locale: posix), "13.2")
        XCTAssertEqual(Metric.heartRateVariability.formatted(74.14, locale: posix), "74")
    }

    func testSections() {
        XCTAssertEqual(Metric.allCases.filter { $0.section == .scores }, [.recovery, .strain, .sleepPerformance])
    }
}
```

`ReflexWhoopTests/HistoryRangeTests.swift`
```swift
import XCTest
@testable import ReflexWhoop

final class HistoryRangeTests: XCTestCase {
    func testFirstDayCountsTodayAsDayOne() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-12T12:00:00Z"))
        XCTAssertEqual(HistoryRange.thirtyDays.firstDay(endingOn: now), "2026-08-14")
        XCTAssertEqual(HistoryRange.ninetyDays.firstDay(endingOn: now), "2026-06-15")
        XCTAssertNil(HistoryRange.all.firstDay(endingOn: now))
    }
}
```

`ReflexWhoopTests/ContinuousRunsTests.swift`
```swift
import XCTest
@testable import ReflexWhoop

final class ContinuousRunsTests: XCTestCase {
    private func at(_ minute: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(minute * 60)) }

    func testEmptyInputHasNoRuns() {
        XCTAssertTrue(ContinuousRuns.split([Date](), maximumGap: 60, time: { $0 }).isEmpty)
    }

    func testBreaksOnlyWhereTheGapExceedsTheMaximum() {
        let times = [0, 1, 2, 10, 11, 30].map(at)
        let runs = ContinuousRuns.split(times, maximumGap: 180, time: { $0 })
        XCTAssertEqual(runs.map(\.count), [3, 2, 1])
    }

    func testGapEqualToMaximumStaysJoined() {
        XCTAssertEqual(ContinuousRuns.split([at(0), at(3)], maximumGap: 180, time: { $0 }).count, 1)
    }
}
```

Extend `ReflexWhoopTests/RecordDAOTests.swift` with:
```swift
    func testDayStringRoundTripsThroughDate() throws {
        let date = try XCTUnwrap(RecordDAO.date(forDay: "2026-09-12"))
        XCTAssertEqual(RecordDAO.dayString(for: date), "2026-09-12")
        XCTAssertNil(RecordDAO.date(forDay: "12/09/2026"))
    }
```

- [ ] **Step 2:** `ruby scripts/generate_project.rb`, run tests. Expected: build fails, missing types.

- [ ] **Step 3: Implement.**

`Analysis/NormalRange.swift`
```swift
import Foundation

/// A person's usual range for one metric on one day: the mean and standard
/// deviation of the days before it, as `BaselineEngine` stores them.
///
/// Every range the app draws uses the window `AnomalyEngine` flags unusual days
/// against, so a reading can never look normal on one screen and be listed as
/// unusual on another.
struct NormalRange: Equatable {
    static let windowDays = AnomalyEngine.baselineWindow

    let mean: Double
    let standardDeviation: Double

    var lowerBound: Double { mean - standardDeviation }
    var upperBound: Double { mean + standardDeviation }

    /// `nil` when the history has no spread to measure against.
    func zScore(of value: Double) -> Double? {
        guard standardDeviation > 0 else { return nil }
        return (value - mean) / standardDeviation
    }
}
```

`Analysis/ReadingStatus.swift`
```swift
import Foundation

/// Where a reading sits relative to the person's own normal. Deliberately
/// neutral about direction: above normal is not automatically good.
enum ReadingStatus: Equatable {
    case within, above, below, unusuallyHigh, unusuallyLow, noReading, notEnoughHistory

    static func classify(_ value: Double?, against range: NormalRange?) -> ReadingStatus {
        guard let value else { return .noReading }
        guard let range, let z = range.zScore(of: value) else { return .notEnoughHistory }
        let unusual = AnomalyEngine.singleMetricThreshold
        return switch z {
        case unusual...: .unusuallyHigh
        case ...(-unusual): .unusuallyLow
        case 1...: .above
        case ...(-1): .below
        default: .within
        }
    }

    var isUnusual: Bool { self == .unusuallyHigh || self == .unusuallyLow }

    var label: String {
        switch self {
        case .within: "Within your normal"
        case .above: "Above your normal"
        case .below: "Below your normal"
        case .unusuallyHigh: "Unusually high"
        case .unusuallyLow: "Unusually low"
        case .noReading: "No reading"
        case .notEnoughHistory: "Not enough history yet"
        }
    }
}
```

`Analysis/RecoveryBand.swift`
```swift
import Foundation

/// WHOOP's recovery bands, on WHOOP's own edges so a score reads the same here
/// as it does in WHOOP's app.
enum RecoveryBand: Equatable {
    case low, moderate, high

    static let illnessNote = "Several signals are off from your normal."

    init(score: Double) {
        self = switch score {
        case ..<34: .low
        case ..<67: .moderate
        default: .high
        }
    }

    var label: String {
        switch self {
        case .low: "Low"
        case .moderate: "Moderate"
        case .high: "High"
        }
    }

    /// Never quotes sleep debt: its input is WHOOP's capped extra-need term,
    /// not debt owed (docs/DECISIONS.md).
    var verdict: String {
        switch self {
        case .low: "Low recovery. Keep today easy."
        case .moderate: "Moderate recovery. Train, but keep something in reserve."
        case .high: "Well recovered. A good day to train hard."
        }
    }
}
```

`Analysis/StrainBand.swift`
```swift
import Foundation

/// WHOOP's day strain categories on its 0–21 scale.
enum StrainBand: Equatable {
    case light, moderate, high, allOut

    static let scaleMaximum = 21.0

    init(strain: Double) {
        self = switch strain {
        case ..<10: .light
        case ..<14: .moderate
        case ..<18: .high
        default: .allOut
        }
    }

    var label: String {
        switch self {
        case .light: "Light"
        case .moderate: "Moderate"
        case .high: "High"
        case .allOut: "All out"
        }
    }
}
```

`Analysis/Metric.swift`
```swift
import Foundation

/// The daily metrics the app shows, and what a screen needs to present one.
///
/// Readiness is deliberately not here: it is hidden until its sleep-debt input
/// is rebuilt (docs/DECISIONS.md, "Readiness hidden").
enum Metric: String, CaseIterable, Identifiable, Hashable {
    case recovery, strain, sleepPerformance
    case heartRateVariability, restingHeartRate, breathingRate, skinTemperature, bloodOxygen

    enum Section: CaseIterable {
        case scores, overnight
    }

    var id: String { rawValue }

    /// The `daily_metrics` column, which is also the `baselines.metric` key.
    var column: String {
        switch self {
        case .recovery: "recovery_score"
        case .strain: "day_strain"
        case .sleepPerformance: "sleep_performance_percentage"
        case .heartRateVariability: "hrv_rmssd_milli"
        case .restingHeartRate: "resting_heart_rate"
        case .breathingRate: "respiratory_rate"
        case .skinTemperature: "skin_temp_celsius"
        case .bloodOxygen: "spo2_percentage"
        }
    }

    var label: String {
        switch self {
        case .recovery: "Recovery"
        case .strain: "Strain"
        case .sleepPerformance: "Sleep performance"
        case .heartRateVariability: "Heart rate variability"
        case .restingHeartRate: "Resting heart rate"
        case .breathingRate: "Breathing rate"
        case .skinTemperature: "Skin temperature"
        case .bloodOxygen: "Blood oxygen"
        }
    }

    /// Short enough for a navigation bar title.
    var shortLabel: String { self == .heartRateVariability ? "HRV" : label }

    var unit: String {
        switch self {
        case .recovery, .sleepPerformance, .bloodOxygen: "%"
        case .strain: ""
        case .heartRateVariability: "ms"
        case .restingHeartRate: "bpm"
        case .breathingRate: "/min"
        case .skinTemperature: "°C"
        }
    }

    var fractionDigits: Int {
        switch self {
        case .strain, .breathingRate, .skinTemperature, .bloodOxygen: 1
        case .recovery, .sleepPerformance, .heartRateVariability, .restingHeartRate: 0
        }
    }

    var section: Section {
        switch self {
        case .recovery, .strain, .sleepPerformance: .scores
        case .heartRateVariability, .restingHeartRate, .breathingRate, .skinTemperature, .bloodOxygen: .overnight
        }
    }

    /// Whether `BaselineEngine` keeps a normal range for this metric.
    var hasNormalRange: Bool { BaselineEngine.metrics.contains(column) }

    func formatted(_ value: Double, locale: Locale = .current) -> String {
        value.formatted(.number.precision(.fractionLength(fractionDigits)).locale(locale))
    }

    init?(column: String) {
        guard let match = Self.allCases.first(where: { $0.column == column }) else { return nil }
        self = match
    }
}
```

`Analysis/HistoryRange.swift`
```swift
import Foundation

/// The spans Trends offers. A span of N days includes today as day one.
enum HistoryRange: String, CaseIterable, Identifiable {
    case thirtyDays, ninetyDays, year, all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .thirtyDays: "30D"
        case .ninetyDays: "90D"
        case .year: "1Y"
        case .all: "All"
        }
    }

    var days: Int? {
        switch self {
        case .thirtyDays: 30
        case .ninetyDays: 90
        case .year: 365
        case .all: nil
        }
    }

    /// First `yyyy-MM-dd` day to include, or `nil` for all history.
    func firstDay(endingOn now: Date) -> String? {
        days.map { RecordDAO.dayString(for: now.addingTimeInterval(-Double($0 - 1) * 86_400)) }
    }
}
```

`Analysis/ContinuousRuns.swift`
```swift
import Foundation

/// Splits time-ordered samples wherever neighbours are further apart than
/// `maximumGap`, so a chart breaks its line where there are no readings
/// instead of drawing a straight line that looks like data.
enum ContinuousRuns {
    static func split<Sample>(_ samples: [Sample], maximumGap: TimeInterval, time: (Sample) -> Date) -> [[Sample]] {
        var runs: [[Sample]] = []
        for sample in samples {
            if let previous = runs.last?.last, time(sample).timeIntervalSince(time(previous)) <= maximumGap {
                runs[runs.count - 1].append(sample)
            } else {
                runs.append([sample])
            }
        }
        return runs
    }
}
```

`Store/DAO/RecordDAO.swift` — add below `dayString(for:)`:
```swift
    /// Inverse of `dayString(for:)`: midnight UTC of a `yyyy-MM-dd` day.
    static func date(forDay day: String) -> Date? {
        dayFormatter.date(from: day)
    }
```
Then in `DailyMetricsBuilder.swift` and `CorrelationEngine.swift` replace their private `dayFormatter` parsing with `RecordDAO.date(forDay:)` and delete the now-unused private formatters (read each file first; only remove a formatter once no call site uses it).

`Analysis/AnomalyEngine.swift`: make `singleMetricThreshold` and `baselineWindow` `static let` (not `private`); add
```swift
    /// The `anomalies.kind` values this engine writes.
    enum Kind: String {
        case illnessFlag = "illness_flag"
        case singleMetricExcursion = "single_metric_excursion"
    }
```
and bind `Kind.illnessFlag.rawValue` / `Kind.singleMetricExcursion.rawValue` as SQL arguments instead of the string literals.

- [ ] **Step 4:** Generate project, run tests. Expected: all pass (122 + new).
- [ ] **Step 5:** Commit `Add domain types for metrics, normal ranges and bands`.

### Task 3: Read models — Today, metric history, recordings, unusual days, archive size

**Files:**
- Create: `Analysis/TodaySnapshot.swift`, `MetricPoint.swift`, `MetricHistory.swift`, `HeartRateReading.swift`, `RecordingSummary.swift`, `RecordingQueries.swift`, `UnusualReading.swift`, `UnusualDay.swift`, `UnusualDays.swift`
- Modify: `Analysis/AnalysisQueries.swift`, `Store/Database.swift`
- Test: `ReflexWhoopTests/ReadModelTests.swift`, `RecordingQueriesTests.swift`, extend `DatabaseTests.swift`

**Interfaces:**
- Consumes: Task 2 types.
- Produces:
```swift
extension AnalysisQueries {
  static func normalRanges(_ db: GRDB.Database, day: String) throws -> [Metric: NormalRange]
  static func normalRanges(_ db: GRDB.Database, metric: Metric, sinceDay: String?) throws -> [String: NormalRange] }
struct LatestSleepDetail { ...existing...; var performancePercentage: Double?; var asleepMilli: Int64? }
struct TodaySnapshot { let metrics: DailyMetricsRow; let ranges: [Metric: NormalRange]; let sleep: LatestSleepDetail?; let anomalies: [AnomalyRow]; let lastSyncedAt: Date?
  var hasIllnessFlag: Bool; func value(of: Metric) -> Double?; func status(of: Metric) -> ReadingStatus
  static func load(_ db: GRDB.Database) throws -> TodaySnapshot? }
struct MetricPoint: Identifiable, Equatable { let day: String; let date: Date; let value: Double; let range: NormalRange?; var id: String; var status: ReadingStatus }
enum MetricHistory { static func points(_ db: GRDB.Database, metric: Metric, sinceDay: String?) throws -> [MetricPoint] }
struct HeartRateReading: Identifiable, Equatable { let time: Date; let bpm: Double; var id: Date }
struct RecordingSummary: Identifiable, Hashable { let id: String; let startedAt: Date; let firstReadingAt: Date?; let lastReadingAt: Date?; let minutesWithReadings: Int; let readingCount: Int; let averageBpm: Double?; let lowestBpm: Int?; let highestBpm: Int?; var span: TimeInterval? }
enum RecordingQueries { static func recent(_ db: GRDB.Database, limit: Int?) throws -> [RecordingSummary]; static func minuteReadings(_ db: GRDB.Database, sessionID: String) throws -> [HeartRateReading] }
struct UnusualReading: Identifiable { let metric: Metric; let value: Double; let range: NormalRange; var status: ReadingStatus; var id: Metric }
struct UnusualDay: Identifiable { let day: String; let date: Date; let isPossibleIllness: Bool; let readings: [UnusualReading]; var id: String }
enum UnusualDays { static func load(_ db: GRDB.Database, sinceDay: String?) throws -> [UnusualDay] }
extension Database { let path: String; func onDiskByteCount() -> Int64 }
```
`DailyMetricsRow.value(for:)` takes `Metric`; `readinessScore` and `TrendMetric` are removed in Task 10 (old views still reference them until then).

- [ ] **Step 1: Write failing tests** (`ReadModelTests.swift`):
```swift
import XCTest
import GRDB
@testable import ReflexWhoop

final class ReadModelTests: XCTestCase {
    private var database: ReflexWhoop.Database!

    override func setUpWithError() throws {
        database = try TestSupport.makeDatabase()
    }

    private func insertDay(_ day: String, recovery: Double? = nil, hrv: Double? = nil, spo2: Double? = nil) throws {
        try database.dbPool.write { db in
            try db.execute(
                sql: """
                INSERT INTO daily_metrics (day, recovery_score, hrv_rmssd_milli, spo2_percentage, algo_version, computed_at)
                VALUES (?, ?, ?, ?, 1, 0)
                """,
                arguments: [day, recovery, hrv, spo2]
            )
        }
    }

    private func insertBaseline(_ metric: String, day: String, mean: Double, stddev: Double, window: Int = NormalRange.windowDays) throws {
        try database.dbPool.write { db in
            try db.execute(
                sql: """
                INSERT INTO baselines (metric, day, window_days, mean_val, stddev_val, z_score, algo_version, computed_at)
                VALUES (?, ?, ?, ?, ?, NULL, 1, 0)
                """,
                arguments: [metric, day, window, mean, stddev]
            )
        }
    }

    private func insertAnomaly(day: String, kind: AnomalyEngine.Kind, metric: String?) throws {
        try database.dbPool.write { db in
            try db.execute(
                sql: "INSERT INTO anomalies (day, kind, metric, z_score, algo_version, computed_at) VALUES (?, ?, ?, 2.5, 1, 0)",
                arguments: [day, kind.rawValue, metric]
            )
        }
    }

    func testTodayIsNilWithNoDays() throws {
        XCTAssertNil(try database.dbPool.read(TodaySnapshot.load))
    }

    func testTodayUsesLatestDayAndOnlyTheSixtyDayWindow() throws {
        try insertDay("2026-09-11", recovery: 40, hrv: 50)
        try insertDay("2026-09-12", recovery: 85, hrv: 74)
        try insertBaseline("hrv_rmssd_milli", day: "2026-09-12", mean: 64, stddev: 6)
        try insertBaseline("hrv_rmssd_milli", day: "2026-09-12", mean: 99, stddev: 1, window: 30)
        try insertAnomaly(day: "2026-09-12", kind: .illnessFlag, metric: nil)

        let today = try XCTUnwrap(try database.dbPool.read(TodaySnapshot.load))
        XCTAssertEqual(today.metrics.day, "2026-09-12")
        XCTAssertEqual(today.ranges[.heartRateVariability], NormalRange(mean: 64, standardDeviation: 6))
        XCTAssertEqual(today.status(of: .heartRateVariability), .above)
        XCTAssertEqual(today.status(of: .bloodOxygen), .noReading)
        XCTAssertEqual(today.status(of: .recovery), .notEnoughHistory)
        XCTAssertTrue(today.hasIllnessFlag)
    }

    func testHistorySkipsMissingValuesAndAttachesPerDayRanges() throws {
        try insertDay("2026-09-10", hrv: 60)
        try insertDay("2026-09-11")
        try insertDay("2026-09-12", hrv: 74)
        try insertBaseline("hrv_rmssd_milli", day: "2026-09-12", mean: 64, stddev: 6)

        let points = try database.dbPool.read { try MetricHistory.points($0, metric: .heartRateVariability, sinceDay: "2026-09-10") }
        XCTAssertEqual(points.map(\.day), ["2026-09-10", "2026-09-12"])
        XCTAssertNil(points[0].range)
        XCTAssertEqual(points[1].status, .above)
    }

    func testUnusualDaysGroupByDayWithValuesAndRanges() throws {
        try insertDay("2026-09-09", hrv: 52)
        try insertBaseline("hrv_rmssd_milli", day: "2026-09-09", mean: 64, stddev: 5)
        try insertAnomaly(day: "2026-09-09", kind: .singleMetricExcursion, metric: "hrv_rmssd_milli")
        try insertAnomaly(day: "2026-08-30", kind: .illnessFlag, metric: nil)

        let days = try database.dbPool.read { try UnusualDays.load($0, sinceDay: nil) }
        XCTAssertEqual(days.map(\.day), ["2026-09-09", "2026-08-30"])
        XCTAssertEqual(days[0].readings.map(\.metric), [.heartRateVariability])
        XCTAssertEqual(days[0].readings[0].status, .unusuallyLow)
        XCTAssertTrue(days[1].isPossibleIllness)
    }
}
```

`RecordingQueriesTests.swift`:
```swift
import XCTest
import GRDB
@testable import ReflexWhoop

final class RecordingQueriesTests: XCTestCase {
    private var database: ReflexWhoop.Database!

    override func setUpWithError() throws {
        database = try TestSupport.makeDatabase()
        try database.dbPool.write { db in
            try db.execute(sql: "INSERT INTO ble_sessions (id, started_at, mode, sample_count, dropped_count, byte_count) VALUES ('old', 1000, 'continuous', 0, 0, 0)")
            try db.execute(sql: "INSERT INTO ble_sessions (id, started_at, mode, sample_count, dropped_count, byte_count) VALUES ('new', 5000, 'continuous', 0, 0, 0)")
            try db.execute(
                sql: """
                INSERT INTO session_metrics (session_id, algo_version, computed_at, hr_mean, hr_min, hr_max, hr_sample_count)
                VALUES ('new', 1, 0, 71.4, 59, 104, 1104)
                """
            )
            for (minute, mean) in [(0, 67.0), (60, 62.0), (600, 99.0)] {
                try db.execute(
                    sql: "INSERT INTO ts_rollup_minute (channel, session_id, minute_start, mean_val, min_val, max_val, sample_count) VALUES (?, 'new', ?, ?, ?, ?, 60)",
                    arguments: [BleNormalizer.Channel.heartRate, 5040 + minute, mean, mean - 2, mean + 2]
                )
            }
        }
    }

    func testRecentIsNewestFirstAndKeepsEmptySessions() throws {
        let recordings = try database.dbPool.read { try RecordingQueries.recent($0, limit: nil) }
        XCTAssertEqual(recordings.map(\.id), ["new", "old"])
        XCTAssertEqual(recordings[1].readingCount, 0)
        XCTAssertNil(recordings[1].averageBpm)
    }

    func testSummaryUsesRollupMinutesForTheSpan() throws {
        let recording = try XCTUnwrap(try database.dbPool.read { try RecordingQueries.recent($0, limit: 1) }.first)
        XCTAssertEqual(recording.minutesWithReadings, 3)
        XCTAssertEqual(recording.readingCount, 1104)
        XCTAssertEqual(recording.lowestBpm, 59)
        XCTAssertEqual(recording.highestBpm, 104)
        XCTAssertEqual(recording.firstReadingAt, Date(timeIntervalSince1970: 5040))
        XCTAssertEqual(recording.span, 600)
    }

    func testMinuteReadingsAreChronological() throws {
        let readings = try database.dbPool.read { try RecordingQueries.minuteReadings($0, sessionID: "new") }
        XCTAssertEqual(readings.map(\.bpm), [67, 62, 99])
    }
}
```
Extend `DatabaseTests.swift`:
```swift
    func testOnDiskByteCountIncludesTheWriteAheadLog() throws {
        let database = try TestSupport.makeDatabase()
        XCTAssertGreaterThan(database.onDiskByteCount(), 0)
    }
```

- [ ] **Step 2:** Generate, run. Expected: compile failures for missing types.

- [ ] **Step 3: Implement.**

In `AnalysisQueries.swift`: change `value(for:)` to take `Metric`:
```swift
    func value(for metric: Metric) -> Double? {
        switch metric {
        case .recovery: recoveryScore
        case .strain: dayStrain
        case .sleepPerformance: sleepPerformancePercentage
        case .heartRateVariability: hrvRmssdMilli
        case .restingHeartRate: restingHeartRate
        case .breathingRate: respiratoryRate
        case .skinTemperature: skinTempCelsius
        case .bloodOxygen: spo2Percentage
        }
    }
```
Replace `baselineBand(_:metric:sinceDay:window:)` with:
```swift
    /// Each day's normal range for one metric, keyed by day.
    static func normalRanges(_ db: GRDB.Database, metric: Metric, sinceDay: String?) throws -> [String: NormalRange] {
        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT day, mean_val, stddev_val FROM baselines
            WHERE metric = ? AND window_days = ? AND (? IS NULL OR day >= ?)
            """,
            arguments: [metric.column, NormalRange.windowDays, sinceDay, sinceDay]
        )
        return Dictionary(uniqueKeysWithValues: rows.compactMap { row -> (String, NormalRange)? in
            guard let mean = row["mean_val"] as Double?, let stddev = row["stddev_val"] as Double? else { return nil }
            return (row["day"], NormalRange(mean: mean, standardDeviation: stddev))
        })
    }

    /// Every metric's normal range on one day.
    static func normalRanges(_ db: GRDB.Database, day: String) throws -> [Metric: NormalRange] {
        let rows = try Row.fetchAll(
            db,
            sql: "SELECT metric, mean_val, stddev_val FROM baselines WHERE day = ? AND window_days = ?",
            arguments: [day, NormalRange.windowDays]
        )
        return Dictionary(uniqueKeysWithValues: rows.compactMap { row -> (Metric, NormalRange)? in
            guard let metric = Metric(column: row["metric"]),
                  let mean = row["mean_val"] as Double?, let stddev = row["stddev_val"] as Double? else { return nil }
            return (metric, NormalRange(mean: mean, standardDeviation: stddev))
        })
    }
```
Keep the old `baselineBand` until Task 10 deletes `TrendsView` (its only caller), then delete it there.

Extend `LatestSleepDetail` with `performancePercentage` (`sleep_performance_percentage`) added to the SELECT, and:
```swift
    /// Light + deep + REM. `nil` when WHOOP sent no stage totals.
    var asleepMilli: Int64? {
        guard lightMs != nil || swsMs != nil || remMs != nil else { return nil }
        return (lightMs ?? 0) + (swsMs ?? 0) + (remMs ?? 0)
    }
```

`Analysis/TodaySnapshot.swift`
```swift
import Foundation
import GRDB

/// Everything Today shows, read in one pass for the most recent day WHOOP
/// scored.
struct TodaySnapshot {
    let metrics: DailyMetricsRow
    let ranges: [Metric: NormalRange]
    let sleep: LatestSleepDetail?
    let anomalies: [AnomalyRow]
    let lastSyncedAt: Date?

    var hasIllnessFlag: Bool {
        anomalies.contains { $0.kind == AnomalyEngine.Kind.illnessFlag.rawValue }
    }

    func value(of metric: Metric) -> Double? { metrics.value(for: metric) }

    func status(of metric: Metric) -> ReadingStatus {
        .classify(value(of: metric), against: ranges[metric])
    }

    static func load(_ db: GRDB.Database) throws -> TodaySnapshot? {
        guard let metrics = try AnalysisQueries.latestDailyMetrics(db) else { return nil }
        return TodaySnapshot(
            metrics: metrics,
            ranges: try AnalysisQueries.normalRanges(db, day: metrics.day),
            sleep: try AnalysisQueries.latestSleepDetail(db),
            anomalies: try AnalysisQueries.anomalies(db, day: metrics.day),
            lastSyncedAt: try AnalysisQueries.lastSyncedAt(db)
        )
    }
}
```

`Analysis/MetricPoint.swift`
```swift
import Foundation

/// One day's value for a metric, with that day's normal range when one exists.
struct MetricPoint: Identifiable, Equatable {
    let day: String
    let date: Date
    let value: Double
    let range: NormalRange?

    var id: String { day }
    var status: ReadingStatus { .classify(value, against: range) }
}
```

`Analysis/MetricHistory.swift`
```swift
import Foundation
import GRDB

enum MetricHistory {
    /// Days with a value only — a day without one is absent, never zero.
    static func points(_ db: GRDB.Database, metric: Metric, sinceDay: String?) throws -> [MetricPoint] {
        let ranges = metric.hasNormalRange ? try AnalysisQueries.normalRanges(db, metric: metric, sinceDay: sinceDay) : [:]
        return try AnalysisQueries.dailyMetrics(db, sinceDay: sinceDay).compactMap { row in
            guard let value = row.value(for: metric), let date = RecordDAO.date(forDay: row.day) else { return nil }
            return MetricPoint(day: row.day, date: date, value: value, range: ranges[row.day])
        }
    }
}
```

`Analysis/HeartRateReading.swift`
```swift
import Foundation

/// A heart-rate value at a moment: a live reading, or a one-minute average
/// from a recording.
struct HeartRateReading: Identifiable, Equatable {
    let time: Date
    let bpm: Double

    var id: Date { time }
}
```

`Analysis/RecordingSummary.swift`
```swift
import Foundation

/// One band recording as the Band tab lists it.
struct RecordingSummary: Identifiable, Hashable {
    let id: String
    let startedAt: Date
    let firstReadingAt: Date?
    let lastReadingAt: Date?
    let minutesWithReadings: Int
    let readingCount: Int
    let averageBpm: Double?
    let lowestBpm: Int?
    let highestBpm: Int?

    /// First to last reading. `nil` when nothing was captured.
    var span: TimeInterval? {
        guard let firstReadingAt, let lastReadingAt else { return nil }
        return lastReadingAt.timeIntervalSince(firstReadingAt)
    }
}
```

`Analysis/RecordingQueries.swift`
```swift
import Foundation
import GRDB

enum RecordingQueries {
    /// Newest first. Sessions that captured nothing are kept: an empty
    /// recording is a fact about the band, not something to hide.
    static func recent(_ db: GRDB.Database, limit: Int?) throws -> [RecordingSummary] {
        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT b.id, b.started_at,
                   m.hr_mean, m.hr_min, m.hr_max, COALESCE(m.hr_sample_count, 0) AS reading_count,
                   r.first_minute, r.last_minute, COALESCE(r.minutes, 0) AS minutes
            FROM ble_sessions b
            LEFT JOIN session_metrics m ON m.session_id = b.id
            LEFT JOIN (
                SELECT session_id, MIN(minute_start) AS first_minute, MAX(minute_start) AS last_minute, COUNT(*) AS minutes
                FROM ts_rollup_minute WHERE channel = ? GROUP BY session_id
            ) r ON r.session_id = b.id
            ORDER BY b.started_at DESC
            LIMIT ?
            """,
            arguments: [BleNormalizer.Channel.heartRate, limit ?? -1]
        )
        return rows.map { row in
            RecordingSummary(
                id: row["id"],
                startedAt: Date(timeIntervalSince1970: TimeInterval(row["started_at"] as Int64)),
                firstReadingAt: (row["first_minute"] as Int64?).map { Date(timeIntervalSince1970: TimeInterval($0)) },
                lastReadingAt: (row["last_minute"] as Int64?).map { Date(timeIntervalSince1970: TimeInterval($0)) },
                minutesWithReadings: row["minutes"],
                readingCount: row["reading_count"],
                averageBpm: row["hr_mean"],
                lowestBpm: row["hr_min"],
                highestBpm: row["hr_max"]
            )
        }
    }

    static func minuteReadings(_ db: GRDB.Database, sessionID: String) throws -> [HeartRateReading] {
        try Row.fetchAll(
            db,
            sql: """
            SELECT minute_start, mean_val FROM ts_rollup_minute
            WHERE channel = ? AND session_id = ? AND mean_val IS NOT NULL
            ORDER BY minute_start
            """,
            arguments: [BleNormalizer.Channel.heartRate, sessionID]
        ).map { row in
            HeartRateReading(time: Date(timeIntervalSince1970: TimeInterval(row["minute_start"] as Int64)), bpm: row["mean_val"])
        }
    }
}
```

`Analysis/UnusualReading.swift`
```swift
import Foundation

struct UnusualReading: Identifiable {
    let metric: Metric
    let value: Double
    let range: NormalRange

    var id: Metric { metric }
    var status: ReadingStatus { .classify(value, against: range) }
}
```

`Analysis/UnusualDay.swift`
```swift
import Foundation

/// A day `AnomalyEngine` flagged, with each flagged reading and the range it
/// was flagged against.
struct UnusualDay: Identifiable {
    let day: String
    let date: Date
    let isPossibleIllness: Bool
    let readings: [UnusualReading]

    var id: String { day }
}
```

`Analysis/UnusualDays.swift`
```swift
import Foundation
import GRDB

enum UnusualDays {
    /// Newest first.
    static func load(_ db: GRDB.Database, sinceDay: String?) throws -> [UnusualDay] {
        let anomalies = try AnalysisQueries.anomalies(db, sinceDay: sinceDay)
        let byDay = Dictionary(grouping: anomalies, by: \.day)
        return try byDay.keys.sorted(by: >).compactMap { day in
            guard let date = RecordDAO.date(forDay: day), let rows = byDay[day] else { return nil }
            let metrics = try DailyMetricsRow.fetchOne(db, sql: "SELECT * FROM daily_metrics WHERE day = ?", arguments: [day])
            let ranges = try AnalysisQueries.normalRanges(db, day: day)
            let readings = rows.compactMap { row -> UnusualReading? in
                guard row.kind == AnomalyEngine.Kind.singleMetricExcursion.rawValue,
                      let metric = row.metric.flatMap(Metric.init(column:)),
                      let value = metrics?.value(for: metric), let range = ranges[metric] else { return nil }
                return UnusualReading(metric: metric, value: value, range: range)
            }
            return UnusualDay(
                day: day,
                date: date,
                isPossibleIllness: rows.contains { $0.kind == AnomalyEngine.Kind.illnessFlag.rawValue },
                readings: readings
            )
        }
    }
}
```

`Store/Database.swift`: add `let path: String`, assign `self.path = path` first in `init`, and:
```swift
    /// Bytes the store occupies, including its write-ahead log and shared memory file.
    func onDiskByteCount() -> Int64 {
        ["", "-wal", "-shm"].reduce(0) { total, suffix in
            let size = (try? FileManager.default.attributesOfItem(atPath: path + suffix)[.size] as? NSNumber)?.int64Value
            return total + (size ?? 0)
        }
    }
```

- [ ] **Step 4:** Generate, run tests. Expected: all pass.
- [ ] **Step 5:** Commit `Add read models for Today, history, recordings and unusual days`.

### Task 4: BLE — structured unavailability and the live heart-rate window

**Files:** Create `Ble/HeartRateWindow.swift`; Modify `Ble/BandConnection.swift:18-27,165-176`, `Ble/SpikeRecorder.swift`, `UI/LiveView.swift` (compile only — deleted in Task 8); Test `ReflexWhoopTests/HeartRateWindowTests.swift`

**Interfaces — Produces:**
```swift
enum BandConnection.Unavailability: Equatable { case poweredOff, unauthorized, unsupported }
case BandConnection.ConnectionState.unavailable(Unavailability)
struct HeartRateWindow: Equatable { let span: TimeInterval; private(set) var readings: [HeartRateReading]; init(span:); mutating func append(bpm: Int, at: Date); var bpmRange: ClosedRange<Double>? }
SpikeRecorder.recentHeartRate: HeartRateWindow   // 20 minutes
```

- [ ] **Step 1: Failing test** `HeartRateWindowTests.swift`:
```swift
import XCTest
@testable import ReflexWhoop

final class HeartRateWindowTests: XCTestCase {
    private func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

    func testKeepsOnlyTheSpan() {
        var window = HeartRateWindow(span: 60)
        window.append(bpm: 60, at: at(0))
        window.append(bpm: 70, at: at(30))
        window.append(bpm: 80, at: at(61))
        XCTAssertEqual(window.readings.map(\.bpm), [70, 80])
    }

    func testReadingExactlyAtTheEdgeIsKept() {
        var window = HeartRateWindow(span: 60)
        window.append(bpm: 60, at: at(0))
        window.append(bpm: 70, at: at(60))
        XCTAssertEqual(window.readings.count, 2)
    }

    func testRange() {
        var window = HeartRateWindow(span: 600)
        XCTAssertNil(window.bpmRange)
        [72, 59, 104].enumerated().forEach { window.append(bpm: $0.element, at: at(Double($0.offset))) }
        XCTAssertEqual(window.bpmRange, 59...104)
    }
}
```
- [ ] **Step 2:** Generate, run — fails (missing type).
- [ ] **Step 3: Implement** `Ble/HeartRateWindow.swift`:
```swift
import Foundation

/// The last few minutes of live heart rate, for the Band tab's chart. Display
/// state only: every reading is already in the database via the inbox.
struct HeartRateWindow: Equatable {
    let span: TimeInterval
    private(set) var readings: [HeartRateReading] = []

    init(span: TimeInterval) {
        self.span = span
    }

    mutating func append(bpm: Int, at time: Date) {
        readings.append(HeartRateReading(time: time, bpm: Double(bpm)))
        let cutoff = time.addingTimeInterval(-span)
        if let firstKept = readings.firstIndex(where: { $0.time >= cutoff }), firstKept > 0 {
            readings.removeFirst(firstKept)
        }
    }

    var bpmRange: ClosedRange<Double>? {
        guard let lowest = readings.map(\.bpm).min(), let highest = readings.map(\.bpm).max() else { return nil }
        return lowest...highest
    }
}
```
`BandConnection`: add
```swift
    /// Why Core Bluetooth can't be used. A case, not a message, so the UI can
    /// offer the right fix for each.
    enum Unavailability: Equatable {
        case poweredOff, unauthorized, unsupported
    }
```
change `case unavailable(String)` to `case unavailable(Unavailability)` and the three assignments to `.unavailable(.poweredOff)`, `.unavailable(.unauthorized)`, `.unavailable(.unsupported)`. In `SpikeRecorder`: `private(set) var recentHeartRate = HeartRateWindow(span: 20 * 60)` beside `lastHeartRateBpm`; reset it in `startSession`; in `handleRawFrame` after `lastHeartRateBpm = bpm` add `recentHeartRate.append(bpm: Int(bpm), at: receivedAt)`. In `LiveView.describe`, change `case .unavailable(let reason): reason` to `case .unavailable: "Bluetooth unavailable"` (temporary; file deleted in Task 8).
- [ ] **Step 4:** Generate, run tests — pass.
- [ ] **Step 5:** Commit `Structured Bluetooth unavailability and a live heart-rate window`.

### Task 5: Design system and app icon

Load: `swiftui-expert-skill` refs `latest-apis`, `charts`, `charts-accessibility`, `accessibility-patterns`, `text-patterns`; `swiftui-pro` all refs; `ios-hig-design` refs `typography`, `colors-depth`, `accessibility`, `app-icons`; `apple-design` (motion).

**Files (all new under `UI/DesignSystem/`):**
- `Color+RGB.swift` — `extension Color { init(rgb: UInt32) }`.
- `Palette.swift` — `enum Palette` with the spec's tokens as `static let` `Color`s: `background, surface, surfaceRaised, ivory, champagne, onChampagne, jade, amber, garnet, sunstone, roseQuartz, sleepREM, sleepLight, sleepDeep`.
- `Font+Display.swift` — `extension Font { static func display(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font` (`.system(style, design: .serif, weight:)`); `static func heroNumeral(scale: Double) -> Font` (`.system(.largeTitle, design: .serif, weight: .light).scaled(by: scale).monospacedDigit()`) }`.
- `NavigationBarStyle.swift` — `enum NavigationBarStyle { @MainActor static func apply() }` sets `UINavigationBar.appearance()` large-title font to the `.largeTitle` preferred font with `.serif` design and regular weight, and title/large-title colour to `UIColor(Palette.ivory)`. Called once from `ReflexWhoopApp.init`. Doc comment says why UIKit: SwiftUI has no title font API.
- `PrimaryButtonStyle.swift` — `struct PrimaryButtonStyle: ButtonStyle` champagne capsule, `onChampagne` headline label, `minHeight: 52`, full width, 0.97 scale + opacity on press with `.animation(.snappy(duration: 0.15), value:)`, disabled renders `Palette.surfaceRaised` with tertiary label. `extension ButtonStyle where Self == PrimaryButtonStyle { static var primary: Self }`.
- `SectionHeader.swift` — `struct SectionHeader: View { let title: String }` footnote semibold, `.tracking(1.2)`, `.textCase(.uppercase)`, `.foregroundStyle(.secondary)`.
- `StatusLabel.swift` — `struct StatusLabel: View { let text: String; let tint: Color }` 8 pt circle + text, `.accessibilityElement(children: .combine)`.
- `ReadingStatus+Style.swift` — `extension ReadingStatus { var emphasis: Color? }`: `Palette.sunstone` when unusual, otherwise `nil` so callers fall back to the hierarchical `.secondary` style.
- `RecoveryBand+Style.swift` — `extension RecoveryBand { var tint: Color }` garnet / amber / jade.
- `RangeStrip.swift` — `struct RangeStrip: View { let value: Double?; let range: NormalRange? }` drawn in a `Canvas` 16 pt tall: track `Palette.surfaceRaised`, band `.tertiary` ivory, dot ivory (sunstone when unusual) with background-coloured ring; domain mean ± 3.2 SD, dot clamped inside; no dot for nil value; no band for nil range. `.accessibilityElement()`, label from status, value "`formatted value`, usual `lower`–`upper`". Callers pass formatted strings via an `accessibilityValue` parameter: `let accessibilityValue: String`.
- `RecoveryZones.swift` — `struct RecoveryZones: View { let score: Double; let usual: NormalRange? }`: three capsules split at 34/67, only the current band coloured (`RecoveryBand.tint`), others `Palette.surfaceRaised`; ivory ring marker; bracket + caption "Your usual `lo`–`hi`" above when `usual` exists; zone labels below. Uses `GeometryReader` only for proportional positions (no modern alternative for proportional drawing — document).
- `StrainScale.swift` — `struct StrainScale: View { let strain: Double }` 0–21 track, champagne fill to value, tick labels 0 / 10 / 14 / 18 / 21.
- `SleepStage.swift` — `enum SleepStage: CaseIterable { case awake, rem, light, deep; var label: String; var tint: Color; func milli(in: LatestSleepDetail) -> Int64? }`.
- `SleepStageBar.swift` — `struct SleepStageBar: View { let sleep: LatestSleepDetail }` segments proportional to totals, 3 pt gaps, legend grid (2 columns) with durations via `Duration.milliseconds(...).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))`.
- `Sparkline.swift` — `struct Sparkline: View { let points: [MetricPoint] }` Swift Charts: `AreaMark(yStart:yEnd:)` band per point where range exists, `LineMark` per `ContinuousRuns.split(points, maximumGap: 1.5 * 86_400, time: \.date)` run using `series:`, last `PointMark`; axes hidden; `.accessibilityHidden(true)` (row label carries the value).
- `MetricHistoryChart.swift` — `struct MetricHistoryChart: View { let points: [MetricPoint]; let metric: Metric }` same marks plus per-point `PointMark` (sunstone when unusual), trailing y axis, 4 x labels; `.accessibilityChartDescriptor` via a small `AXChartDescriptorRepresentable` struct `MetricHistoryChartDescriptor` in its own file.
- `HeartRateChart.swift` — `struct HeartRateChart: View { let readings: [HeartRateReading]; let maximumGap: TimeInterval }` rose-quartz line per run with 10 % area, trailing y axis; `.accessibilityLabel("Heart rate")` + `.accessibilityValue("lowest–highest bpm")`.
- `HeroValue.swift` — `struct HeroValue: View { let value: String; let unit: String?; var scale: Double = 2.4 }` serif numeral with smaller unit, `.accessibilityElement(children: .combine)`.
- `InlineMessage.swift` — `struct InlineMessage: View { let text: String }` footnote secondary with `exclamationmark.triangle`.

**App icon:**
- Replace `AppIcon.appiconset` contents with `icon-default.png`, `icon-dark.png`, `icon-tinted.png` copied from `../reflex-whoop/design/icon-export/` and `Contents.json`:
```json
{
  "images" : [
    { "filename" : "icon-default.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
    { "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ], "filename" : "icon-dark.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
    { "appearances" : [ { "appearance" : "luminosity", "value" : "tinted" } ], "filename" : "icon-tinted.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```
- `AccentColor.colorset` → champagne `#D3BE99`.

- [ ] **Step 1:** Create the files above; generate project; build. Expected: build succeeds; icon asset compiles without warnings (`grep -i "appicon" build log` empty).
- [ ] **Step 2:** Run tests — all pass.
- [ ] **Step 3:** Commit `Add the Onyx design system and the Your normal app icon`.

### Task 6: Root structure and Today

Load: `swiftui-expert-skill` refs `sheet-navigation-patterns`, `list-patterns`, `state-management`, `view-structure`; `ios-hig-design` `navigation`.

**Files:**
- Create `App/AppTab.swift` — `enum AppTab: Hashable { case today, trends, band, archive }`.
- Modify `UI/RootView.swift` — `TabView(selection: $selection)` with `Tab("Today", systemImage: "sun.max", value: AppTab.today) { TodayView() }`, `Tab("Trends", systemImage: "chart.line.uptrend.xyaxis", value: .trends) { TrendsView() }` (old view until Task 7), `Tab("Band", systemImage: "applewatch", value: .band) { LiveView() }` (until Task 8), `Tab("Archive", systemImage: "archivebox", value: .archive) { DataView() }` (until Task 9); `.tint(Palette.champagne)`; keep the existing `.task`/`.onChange(of: scenePhase)` sync triggers.
- Modify `App/ReflexWhoopApp.swift` — call `NavigationBarStyle.apply()` in `init`; root `.foregroundStyle(Palette.ivory)` and `.background(Palette.background)`.
- Delete `UI/TodayView.swift`. Create `UI/Today/TodayView.swift`, `RecoveryHero.swift`, `StrainRow.swift`, `SleepCard.swift`, `VitalRow.swift`, `TodayEmptyState.swift`, `UI/Metrics/MetricDetailView.swift`, `UI/Metrics/MetricDetailHeader.swift`.

**TodayView contract:**
- `@State private var snapshot: TodaySnapshot?`, `@State private var loadError: String?`, `@State private var hasLoaded = false`; `private func load() async` reads `TodaySnapshot.load` off `container.database.dbPool`; `.task` and `.refreshable` call it.
- `NavigationStack` → `List` `.listStyle(.insetGrouped)`, `.scrollContentBackground(.hidden)`, `.background(Palette.background)`, rows `.listRowBackground(Palette.surface)`; `.navigationTitle("Today")`, `.navigationSubtitle(day formatted .dateTime.weekday(.wide).day().month(.wide))`; `.navigationDestination(for: Metric.self) { MetricDetailView(metric: $0) }`.
- Sections: (1) `RecoveryHero(score:, usual:, hasIllnessFlag:)` on a clear row background — "Recovery" caption, `HeroValue`, band `StatusLabel`, verdict (`RecoveryBand.verdict` + `RecoveryBand.illnessNote` when flagged), `RecoveryZones`; hero is a `NavigationLink(value: Metric.recovery)`. (2) `StrainRow` NavigationLink(value: .strain): "Strain" label, value, "`StrainBand.label` so far", `StrainScale`. (3) header "Last night": `SleepCard(sleep:)` + row "Sleep performance" value NavigationLink(value: .sleepPerformance); caption "Stage totals only. WHOOP doesn't share the order they happened in." (4) header "Overnight vitals": `VitalRow(metric:value:status:range:)` for the five overnight metrics, each NavigationLink; footer "The grey band is your normal over the previous 60 days. The dot is last night." (5) footer line "From WHOOP · synced `relative`".
- Empty: `TodayEmptyState` uses `ContentUnavailableView("Nothing to show yet", systemImage: "sun.max", description: Text("Connect your WHOOP account in Archive, or record from your band."))`.
- Error: `InlineMessage(loadError)` above content.

**MetricDetailView contract** (shared by Today and Trends): `let metric: Metric`; `@State private var range: HistoryRange = .thirtyDays`; `@State private var points: [MetricPoint] = []`; `.task(id: range) { await load() }`; header "Last night"/"Latest" caption, `HeroValue(metric.formatted(latest.value), unit: metric.unit)`, status sentence "`status.label` of `lower`–`upper` `unit`" (or status label alone without a range); `Picker` `.segmented` over `HistoryRange`; `MetricHistoryChart`; stats row Average / Range / Days via `points.map(\.value)` computed in a `MetricHistorySummary` struct (pure, in `Analysis/MetricHistorySummary.swift`, with `average`, `lowest`, `highest`, `count`, tested in `ReadModelTests`); "Unusual days" list of points where `status.isUnusual` (date + value); `.navigationTitle(metric.shortLabel)`, `.navigationBarTitleDisplayMode(.inline)`.

- [ ] **Step 1:** Add `MetricHistorySummary` test to `ReadModelTests` (average/lowest/highest/count for `[60, 74, 50]`, and `nil` for empty), run → fail.
- [ ] **Step 2:** Implement `Analysis/MetricHistorySummary.swift`, the views, RootView and app changes; generate; run tests → pass.
- [ ] **Step 3:** Build and install to the simulator with a copy of the device database (see Task 11 procedure); screenshot Today and HRV detail; fix what the screenshot shows.
- [ ] **Step 4:** Commit `Rebuild Today and metric detail on the Onyx system`.

### Task 7: Trends, Patterns, Unusual days

**Files:** Delete `UI/TrendsView.swift`, `UI/InsightsView.swift`. Create `UI/Trends/TrendsView.swift`, `TrendRow.swift`, `TrendsLink.swift` (`enum TrendsLink: Hashable { case patterns, unusualDays }`), `PatternsView.swift`, `PredictorLabel.swift` (moved verbatim from InsightsView), `UnusualDaysView.swift`, `UnusualDayRows.swift`.

**TrendsView contract:** `@State private var range: HistoryRange = .thirtyDays`; `@State private var history: [Metric: [MetricPoint]] = [:]`; `@State private var unusualDayCount = 0`; `.task(id: range)` loads every metric's points and `UnusualDays.load(sinceDay: HistoryRange.thirtyDays.firstDay(endingOn: .now)).count` in one `dbPool.read`. `List`: segmented `Picker` row; section "Scores" and "Overnight" (from `Metric.Section`) of `TrendRow(metric:points:)` — label, latest formatted value + unit, `Sparkline` (110×34), NavigationLink(value: metric); section "Patterns": `NavigationLink(value: TrendsLink.patterns)` "What goes with your recovery" / subtitle "Nothing stands out yet" when no correlation is stronger than weak, else "`n` possible patterns"; `NavigationLink(value: TrendsLink.unusualDays)` "Unusual days" / "`n` in the last 30 days". Destinations registered once: `Metric.self`, `TrendsLink.self`.

**PatternsView contract:** loads `AnalysisQueries.correlations`; if nothing above `.weak`: title block "Nothing stands out yet" (display font) + "We compared `n` things with how recovered you were the next morning, across `maxN` days. None of them moved with your recovery more than chance would."; section "Closest so far" rows `PredictorLabel.label` + trailing `r ±0.00` (`rho.formatted(.number.precision(.fractionLength(2)).sign(strategy: .always()))`); footer "r runs from −1 to +1, where 0 means no relationship. After allowing for testing `n` things at once, every result has p `p`: about what you'd expect if none of them had anything to do with your recovery." Section "Why no direction is shown" body text from the spec copy rules. If any result is moderate or strong: header "Worth a closer look", rows show the plain sentence "More `name` tends to go with better/worse recovery the next morning." plus r and p, and the same causation footer. Section "Not enough data yet" for `.insufficient` rows with `ProgressView(value: min(n, 30), total: 30)`.

**UnusualDaysView contract:** loads `UnusualDays.load(sinceDay: nil)`; footer at top "Days when a reading was more than twice as far from your normal as it usually strays."; one `Section` per day, header date `.dateTime.weekday(.abbreviated).day().month(.abbreviated)`, header trailing "Possible illness" in sunstone when flagged; rows metric label + "Usually `lower`–`upper` `unit`" + trailing value and status label in sunstone. Illness-only days with no readings show "Several signals moved together the way they often do before feeling ill. A pattern in your numbers, not a diagnosis."

- [ ] **Step 1:** Implement; move the Trends tab in `RootView` to the new `TrendsView`; remove `AnalysisQueries.baselineBand` (last caller gone); generate; build; run tests.
- [ ] **Step 2:** Simulator screenshots of Trends, Patterns, Unusual days; fix.
- [ ] **Step 3:** Commit `Rebuild Trends with Patterns and Unusual days folded in`.

### Task 8: Band

Load: `swift-concurrency-pro` refs `unstructured`, `actors` (recorder lifecycle); `ios-hig-design` `privacy-permissions`.

**Files:** Delete `UI/LiveView.swift`. Create `UI/Band/BandView.swift`, `LiveHeartRateSection.swift`, `BandStateView.swift`, `BandLink.swift` (`enum BandLink: Hashable { case allRecordings, signalDetails }`), `RecordingRow.swift`, `RecordingsListView.swift`, `RecordingDetailView.swift`, `SignalDetailsView.swift`.

**BandView contract:** `@Environment(AppContainer.self)`; `@State private var ownRecorder: SpikeRecorder?`; `@State private var recordings: [RecordingSummary] = []`; `private var recorder: SpikeRecorder? { container.continuousRecorder ?? ownRecorder }`; `@AppStorage` is not used — the Keep recording toggle binds to a `@State private var keepRecording = CollectionSettings.continuousCollectionEnabled` with `.onChange(of: keepRecording) { container.setContinuousCollection(keepRecording) }`. Title "Band", subtitle from state: "Connected · recording" / "Looking for your band" / "Bluetooth is off" / "Not recording".
- State mapping (pure helper `BandPresentation.from(connection:isRecording:)` in `UI/Band/BandPresentation.swift`, an enum `idle, live, searching, bluetoothOff, bluetoothDenied, unsupported`, tested in `ReflexWhoopTests/BandPresentationTests.swift` for every `ConnectionState`).
- `live`: `LiveHeartRateSection` — rose heart symbol, `HeroValue(bpm)`, "Live from your band", card "Last 20 minutes" + `recorder.recentHeartRate.bpmRange` + `HeartRateChart(readings: recorder.recentHeartRate.readings, maximumGap: 10)`.
- `searching`: `BandStateView` glyph `antenna.radiowaves.left.and.right`, "Looking for your band", "Keep it within a few metres. Recording carries on by itself when it reconnects."; footer "Heart rate from while the band is away isn't recorded. ReflexWhoop never reads the band's stored history."
- `bluetoothOff`: "Bluetooth is off" / "Turn it on in Control Center to record from your band."; `bluetoothDenied`: "Bluetooth is turned off for ReflexWhoop" / "The app needs Bluetooth to hear your band. It only ever reads from it." + `Button("Open Settings", action: openSettings)` `.buttonStyle(.primary)` using `openURL(URL(string: UIApplication.openSettingsURLString)!)` guarded with `if let`; `unsupported`: "This iPhone can't use Bluetooth".
- `idle` (no recorder, keep-recording off): "Record from your band" + "Connects straight to the band over Bluetooth. No account or internet needed." + `Button("Start recording", action: startRecording)` `.buttonStyle(.primary)`; when `ownRecorder != nil` and not continuous, a `Button("Stop recording", role: .destructive, action: stopRecording)`.
- Section "Recording": Toggle "Keep recording"; row "This session" "`duration` · `n` readings" when live; footer "Stays connected in the background and reconnects when the band is back in range. No account or internet needed. Uses more battery on both."
- Section "Recent": first 3 `RecordingRow` NavigationLink(value: recording) + `NavigationLink(value: BandLink.allRecordings)` "All recordings" `count`.
- Section: `NavigationLink(value: BandLink.signalDetails)` "Signal details" (only when a recorder exists).
- Footer: `Label("Only reads from your band. It can't change anything on it.", systemImage: "lock")`.
- `.task` loads `RecordingQueries.recent(limit: nil)`; reload when the recorder's `sessionID` changes (`.onChange(of: recorder?.sessionID)`).

**RecordingRow:** date `.dateTime.weekday().hour().minute()`, span `Duration.seconds(span).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))` or "Nothing captured", trailing "`avg` bpm avg".

**RecordingDetailView:** `let recording: RecordingSummary`; loads `minuteReadings`; header date (wide) + "`first` – `last`" time range + "`span` · `n` readings"; three stat tiles Average/Lowest/Highest (grid, `.accessibilityElement(children: .combine)` each); `HeartRateChart(readings:, maximumGap: 180)` + caption "One-minute averages. Breaks are minutes with no readings."; section "What was captured": check `jade` "Heart rate" "Readable · `n` readings"; clock "Motion and optical signals" "Saved as received · not readable yet"; footer "Recordings are kept exactly as the band sent them, so they can be read again as more signals are understood. They're never deleted by the app."

**SignalDetailsView:** `let recorder: SpikeRecorder`; footer "For decoding work. Nothing on this screen changes how the band behaves."; section "This session": Packets received `frameCount`, Read as heart rate `packetTypeCounts` HR count, Usable `validCrcFrameCount`, HR cross-check `hrCrossCheckDiffBpm` when present; footer "Heart rate is one of several signals the band sends, so a low share of readable packets is expected — it isn't a quality problem."; section "Signals the band sent": `packetTypeCounts.sortedByCount` rows `PacketTypeCounts.label(for:)` monospaced + count; section "Band reports": `deviceMetadataStrings` monospaced; section "Startup commands": `commandResults` rows with checkmark/xmark (jade/garnet); section "Safety": lock row "Read-only connection" / "Can't change settings, clock or alarms, and never asks the band for its stored history."

- [ ] **Step 1:** Write `BandPresentationTests` (idle when no recorder; `.ready` → live; `.scanning`/`.connecting`/`.discoveringServices`/`.subscribing`/`.disconnected` → searching; each `Unavailability` → its case), run → fail.
- [ ] **Step 2:** Implement; switch the Band tab; generate; build; tests pass.
- [ ] **Step 3:** Simulator screenshots (idle, recordings list, recording detail); on-device screenshot of live state after Task 11 install; fix.
- [ ] **Step 4:** Commit `Rebuild the Band tab around live heart rate and recordings`.

### Task 9: Archive, WHOOP account, export, rebuild, about

**Files:** Delete `UI/DataView.swift`, `UI/SettingsView.swift`. Create `UI/Archive/ArchiveView.swift`, `ArchiveSummaryHeader.swift`, `ArchiveLink.swift` (`enum ArchiveLink: Hashable { case whoopAccount, about }`), `SourceRow.swift`, `WhoopAccountView.swift`, `WhoopCredentialsForm.swift`, `ExportSheet.swift`, `AboutView.swift`, `SourceState+Presentation.swift` (`extension SourceState { var statusText: String; var tint: Color }`).

**ArchiveView contract:** loads `container.sourceSnapshot()` and `container.database.onDiskByteCount()`; header `ArchiveSummaryHeader(summary:byteCount:)` — `HeroValue("\(dayCount)", unit: "days")`, "`first` – `last`" dates (`RecordDAO.date(forDay:)` formatted `.dateTime.day().month(.wide).year()`), three tiles Recordings / Readings (`bleSampleCount.formatted(.number.notation(.compactName))`) / On disk (`ByteCountFormatStyle`). Section "Sources": `SourceRow` WHOOP account (cloud symbol, `snapshot.whoop.statusText`, tint) NavigationLink(value: ArchiveLink.whoopAccount); Band row (applewatch symbol, "Recording" jade when `continuousRecorder` exists, else band `statusText`) is a `Button` that sets `selectedTab = .band`; `ArchiveView` takes `@Binding var selectedTab: AppTab` from `RootView`. Section "Your data": `Button("Export a copy", systemImage: "square.and.arrow.up", action: showExport)` → `.sheet(isPresented:)` `ExportSheet`; `Button("Rebuild heart-rate history", systemImage: "arrow.clockwise", action: askToRebuild)` with `.confirmationDialog("Rebuild heart-rate history?", isPresented:)` attached to the button — actions `Button("Rebuild", action: rebuild)`; message "Reads all `n` band recordings again to recreate the readings. The recordings themselves aren't changed."; while running show `ProgressView` in the row; result or error text beneath. Footer "The app never deletes anything. Deleting the app does, so keep an exported copy somewhere safe." Section "About": NavigationLink(value: ArchiveLink.about) "How ReflexWhoop works".

**WhoopAccountView contract:** `@Environment(AppContainer.self)`; loads `sourceSnapshot()` and whether credentials exist (`TokenStore.loadClientCredentials() != nil`). States:
- `.active`/`.unreachable`: status block (cloud symbol, `StatusLabel` "Connected" jade or "Can't reach WHOOP" sunstone with reason), "Last synced `relative`"; `Button("Sync now", systemImage: "arrow.clockwise", action: syncNow)` (disabled while working, shows `ProgressView`); footer "Also syncs by itself each time you open the app."; section "History": "`dayCount` days, `first` – `last`"; `Button("Sign out", role: .destructive, action: signOut)` footer "Signing out keeps everything already on this phone."
- `.inactive`: `StatusLabel` "Membership ended" sunstone + "WHOOP stopped sending new data after `lastDay`."; `Button("Check again", action: syncNow)`; footer "If you rejoin, syncing picks up where it stopped."; section "Still works": jade checks "Heart rate from your band", "All `n` days of history", "Trends and patterns on that history", "Exporting a copy"; section "Paused": "New recovery, sleep and strain", "HRV, breathing rate, skin temperature, blood oxygen".
- `.unauthorized`: "Signed out" + `Button("Sign in", action: signIn)`, and `Button("Forget saved credentials", role: .destructive, action: forgetCredentials)`.
- `.notConfigured`: `WhoopCredentialsForm(onConnected:)`.
Every action's error text shows beneath the triggering control.

**WhoopCredentialsForm contract:** title (display font) "Connect your WHOOP account"; body "ReflexWhoop signs in through your own WHOOP developer app. Paste its client ID and secret."; `SecureField("Client ID")`, `SecureField("Secret")` with `.textInputAutocapitalization(.never)`, `.autocorrectionDisabled()`, `.textContentType(.none)`; footer `Label("Kept in this iPhone's Keychain and only used to sign in to WHOOP.", systemImage: "lock")`; `Button("Connect", action: connect)` `.buttonStyle(.primary)` disabled while either field is empty or working; `connect()` saves via `TokenStore.saveClientCredentials`, calls `container.signIn()`, then `onConnected()`; errors inline.

**ExportSheet contract:** `.presentationDetents([.medium, .large])`; title "Export a copy"; subtitle "Files you can open on a computer, saved to Files on this iPhone."; rows Daily scores CSV, Sleep and workouts CSV, Heart-rate recordings CSV, Everything as one database SQLite (static description of what `Exporter` writes — verify the table list in `Exporter.swift` before wording); `Button("Export", action: export)` primary → `Exporter.export(dbPool:exportsRoot: URL.documentsDirectory.appending(path: "exports"))`; done state: check symbol, "Copy saved", "Files › On My iPhone › ReflexWhoop › exports", total rows and `ByteCountFormatStyle` from the manifest, `ShareLink("Share…", item: result.directory)`; errors inline.

**AboutView:** two sections per the spec's About rule, plain `Text` rows.

- [ ] **Step 1:** Add `SourceState+Presentation` tests to `SourceStatusTests` (statusText for each case: "Connected", "Not set up", "Signed out", "Membership ended", "Can't reach WHOOP"), run → fail.
- [ ] **Step 2:** Implement; switch the Archive tab (RootView passes `$selection`); generate; build; tests pass.
- [ ] **Step 3:** Simulator screenshots: Archive, WHOOP account (connected), export sheet, rebuild dialog; fix.
- [ ] **Step 4:** Commit `Replace Data and Settings with Archive`.

### Task 10: First run, cleanup of dead code

**Files:** Create `App/Onboarding.swift`, `UI/Onboarding/OnboardingFlow.swift`, `OnboardingStep.swift` (`enum OnboardingStep: Hashable { case sources, bluetooth, whoop, firstSync }`), `WelcomeStep.swift`, `SourcesStep.swift`, `BluetoothPrimerStep.swift`, `FirstSyncStep.swift`. Delete `UI/Components/Theme.swift` and remove `TrendMetric`, `DailyMetricsRow.readinessScore` + its coding key from `AnalysisQueries.swift`. Modify `UI/RootView.swift`. Test `ReflexWhoopTests/OnboardingTests.swift`.

**Interfaces:** `enum Onboarding { static let completedKey = "hasCompletedOnboarding"; static func shouldPresent(hasCompleted: Bool, archiveIsEmpty: Bool, isSignedIn: Bool) -> Bool }`

- [ ] **Step 1: Failing test:**
```swift
import XCTest
@testable import ReflexWhoop

final class OnboardingTests: XCTestCase {
    func testOnlyAFreshInstallSeesTheFlow() {
        XCTAssertTrue(Onboarding.shouldPresent(hasCompleted: false, archiveIsEmpty: true, isSignedIn: false))
        XCTAssertFalse(Onboarding.shouldPresent(hasCompleted: true, archiveIsEmpty: true, isSignedIn: false))
        XCTAssertFalse(Onboarding.shouldPresent(hasCompleted: false, archiveIsEmpty: false, isSignedIn: false))
        XCTAssertFalse(Onboarding.shouldPresent(hasCompleted: false, archiveIsEmpty: true, isSignedIn: true))
    }
}
```
- [ ] **Step 2: Implement** `App/Onboarding.swift`:
```swift
import Foundation

/// The first-run flow exists to get a new install to its first data. An
/// install that already has data or a signed-in account — including every
/// install that predates the flow — never sees it.
enum Onboarding {
    static let completedKey = "hasCompletedOnboarding"

    static func shouldPresent(hasCompleted: Bool, archiveIsEmpty: Bool, isSignedIn: Bool) -> Bool {
        !hasCompleted && archiveIsEmpty && !isSignedIn
    }
}
```
**RootView:** `@AppStorage(Onboarding.completedKey) private var hasCompletedOnboarding = false`; `@State private var isShowingOnboarding = false`; in `.task` after sync triggers: read `container.sourceSnapshot()`; if `Onboarding.shouldPresent(...)` show, otherwise set `hasCompletedOnboarding = true`; `.fullScreenCover(isPresented:) { OnboardingFlow(onFinish: finishOnboarding) }`.

**OnboardingFlow contract:** `NavigationStack(path:)` over `OnboardingStep`; `@State private var wantsWhoop = true`, `wantsBand = true`.
- `WelcomeStep`: 112 pt app icon image from a new `AppIconPreview.imageset` (`icon-default.png` downscaled to 336 px with `sips -Z 336`), referenced as `Image(.appIconPreview)` if the build generates asset symbols (check `ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS` in the build settings), else `Image("AppIconPreview")`, with `.accessibilityHidden(true)`, "ReflexWhoop" display largeTitle, "Your WHOOP data, kept on your iPhone.", three `Label`s (archivebox "Yours to keep" / "Everything is stored on this iPhone and can be exported whenever you like."; applewatch "Works without a membership" / "Heart rate comes straight from the band over Bluetooth."; chart.dots.scatter "Honest numbers" / "Every reading is shown against your own normal. Missing data stays missing."), `Button("Get started")` primary → `.sources`.
- `SourcesStep`: "Where should data come from?" display title; subtitle "Use either or both. You can change this later in Archive."; two toggle cards (Button with checkmark state, `.accessibilityAddTraits(.isSelected)` when on): WHOOP account "Recovery, sleep, strain and HRV, including your past history." note "Needs an active membership and a free WHOOP developer app."; Band over Bluetooth "Live heart rate straight from the band." note "Needs no account and no internet."; Continue (disabled when neither) → `.bluetooth` if band, else `.whoop` if WHOOP, else finish.
- `BluetoothPrimerStep`: glyph, "Let ReflexWhoop hear your band", "iPhone will ask for Bluetooth access next. It's only used to read from your WHOOP band.", lock row "The app can't change any setting, alarm or clock on the band."; Continue → `container.setContinuousCollection(true)` then next (`.whoop` if wanted, else finish); "Not now" → next without enabling.
- `.whoop` → `WhoopCredentialsForm(onConnected: { path.append(.firstSync) })` plus "Skip for now" → finish.
- `FirstSyncStep`: "Bringing in your history" / "You can start using the app. This carries on in the background."; runs `container.syncEngine()?.syncNow(trigger: "onboarding")` in a `.task`; a second `.task` polls `SourceStatus.archive` every second (`try await Task.sleep(for: .seconds(1))`, stops on cancellation) and shows `HeroValue(dayCount, unit: "days so far")` with an indeterminate `ProgressView` until the sync finishes, then "`n` days ready"; errors inline; `Button("Go to Today", action: onFinish)` primary always enabled.
- `finishOnboarding()`: `hasCompletedOnboarding = true`, dismiss.

- [ ] **Step 3:** Delete Theme and dead analysis API; `grep -rn "Theme\.\|TrendMetric\|readinessScore\|Eyebrow\|Readout(" ReflexWhoop` → no matches; generate; build; run tests → pass.
- [ ] **Step 4:** Simulator: fresh install (no DB) shows onboarding; screenshot each step; install with DB copy skips it.
- [ ] **Step 5:** Commit `Add first-run flow and remove the old visual system`.

### Task 11: Docs, MCP semantics, verification, device install

- [ ] **Step 1:** `docs/DECISIONS.md` — add "Readiness hidden until sleep debt is rebuilt": the finding (`need_from_sleep_debt_milli` is WHOOP's capped extra-need term, 7,668,000 ms on 55 of 69 days; `DailyMetricsBuilder` copies it into `sleep_debt_milli`; `ReadinessEngine.fullDebtOffsetMilli` = 2 h saturates below the cap), the restore condition (own rolling 7-night deficit grouped by `cycle_id`, absolute scale 0 h → 100 / ≥14 h → 0, never present the capped term as debt, capped-term fixture), and "Normal range uses the 60-day window so the UI agrees with AnomalyEngine".
- [ ] **Step 2:** `docs/design.md` UI section: five tabs → Today · Trends · Band · Archive; readiness hidden; Onyx summary with a pointer to the spec.
- [ ] **Step 3:** `mcp-server/server.py` daily-metrics tool docstring: state that `sleep_debt_milli` holds WHOOP's capped `need_from_sleep_debt_milli` (extra need attributed to debt), not debt owed, and that `readiness_score` is not shown in the app pending that fix. Run `python3 -m py_compile mcp-server/server.py`.
- [ ] **Step 4:** Full test run → all pass; `xcodebuild build -configuration Release` for the device destination succeeds.
- [ ] **Step 5:** Visual verification: copy the device DB (`xcrun devicectl device copy from ...`) into the booted simulator's app container after first install, relaunch, screenshot every screen and state reachable with real data; fix defects; delete the copied DB from the simulator afterwards.
- [ ] **Step 6:** Invoke `design:accessibility-review` on the screens (VoiceOver labels, Dynamic Type at AX5 screenshot of Today, contrast of champagne on black and on-champagne text); fix findings.
- [ ] **Step 7:** Invoke `simplify` then `code-review` on the branch diff; apply fixes; re-run tests.
- [ ] **Step 8:** Build for the iPhone and install (`xcrun devicectl device install app`), launch, confirm the icon on the Home Screen and the live Band state with the band worn.
- [ ] **Step 9:** Commit docs; invoke `superpowers:verification-before-completion` and `superpowers:finishing-a-development-branch`.
