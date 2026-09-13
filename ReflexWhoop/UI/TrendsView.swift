import SwiftUI
import Charts

/// Metric x range picker, line chart with the personal baseline band drawn
/// behind it, and a weekday breakdown. Per the design doc's UI principle #2:
/// "no number appears without its normal range" — the band is what turns a bare
/// line into something you can actually read as "high" or "low."
struct TrendsView: View {
    @Environment(AppContainer.self) private var container

    @State private var metric: TrendMetric = .recoveryScore
    @State private var range: RangeOption = .ninety
    @State private var rows: [DailyMetricsRow] = []
    @State private var band: [String: (mean: Double, stddev: Double)] = [:]
    @State private var isLoading = false

    private enum RangeOption: String, CaseIterable, Identifiable {
        case thirty = "30D", ninety = "90D", year = "365D", all = "All"
        var id: String { rawValue }
        var days: Int? {
            switch self {
            case .thirty: 30
            case .ninety: 90
            case .year: 365
            case .all: nil
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ink.ignoresSafeArea()
                if rows.isEmpty && !isLoading {
                    VStack(spacing: 8) {
                        Text("Nothing to chart yet")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Theme.text)
                        Text("Trends appear once a few days have synced.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Theme.gutter) {
                            picker
                            Card {
                                VStack(alignment: .leading, spacing: 14) {
                                    headline
                                    chart
                                }
                            }
                            weekdayBreakdown
                        }
                        .padding(Theme.gutter)
                    }
                }
            }
            .navigationTitle("Trends")
            .toolbarBackground(Theme.ink, for: .navigationBar)
        }
        .task(id: Pair(metric, range)) { await load() }
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Metric", selection: $metric) {
                ForEach(TrendMetric.allCases) { m in Text(m.label).tag(m) }
            }
            .pickerStyle(.menu)
            .tint(Theme.vital)

            Picker("Range", selection: $range) {
                ForEach(RangeOption.allCases) { r in Text(r.rawValue).tag(r) }
            }
            .pickerStyle(.segmented)
        }
    }

    /// The current value stated plainly above the chart, with how it compares
    /// to this person's own normal. A line alone tells you the shape; this
    /// tells you the answer.
    @ViewBuilder
    private var headline: some View {
        let latest = rows.last(where: { $0.value(for: metric) != nil })
        let value = latest?.value(for: metric)
        HStack(alignment: .top) {
            Readout(
                label: metric.label,
                value: value.map { formatted($0) },
                unit: metric.unit.isEmpty ? nil : metric.unit,
                note: comparisonNote(latest),
                size: 30
            )
            Spacer()
        }
    }

    private func formatted(_ value: Double) -> String {
        value >= 100 || value.rounded() == value ? "\(Int(value))" : String(format: "%.1f", value)
    }

    private func comparisonNote(_ row: DailyMetricsRow?) -> String? {
        guard metric.hasBaseline, let row, let value = row.value(for: metric), let b = band[row.day], b.stddev > 0 else {
            return nil
        }
        let z = (value - b.mean) / b.stddev
        if abs(z) < 0.5 { return "Right around your normal" }
        return z > 0 ? "Above your normal" : "Below your normal"
    }

    @ViewBuilder
    private var chart: some View {
        let points = rows.compactMap { row -> (Date, Double)? in
            guard let value = row.value(for: metric), let date = Self.dayFormatter.date(from: row.day) else { return nil }
            return (date, value)
        }

        if points.isEmpty {
            Text("No \(metric.label.lowercased()) in this range")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .frame(height: 200)
        } else {
            Chart {
                if metric.hasBaseline {
                    ForEach(rows) { row in
                        if let b = band[row.day], let date = Self.dayFormatter.date(from: row.day) {
                            AreaMark(
                                x: .value("Day", date),
                                yStart: .value("Normal low", b.mean - b.stddev),
                                yEnd: .value("Normal high", b.mean + b.stddev)
                            )
                            .foregroundStyle(Theme.muted.opacity(0.18))
                        }
                    }
                }
                ForEach(points, id: \.0) { date, value in
                    LineMark(x: .value("Day", date), y: .value(metric.label, value))
                        .foregroundStyle(Theme.vital)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .interpolationMethod(.monotone)
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisGridLine().foregroundStyle(Theme.stroke)
                    AxisValueLabel().foregroundStyle(Theme.muted)
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine().foregroundStyle(Theme.stroke)
                    AxisValueLabel().foregroundStyle(Theme.muted)
                }
            }
            .frame(height: 200)
            .accessibilityLabel("\(metric.label) over \(range.rawValue)")
            .accessibilityValue(trendSummary(points))

            if metric.hasBaseline {
                HStack(spacing: 6) {
                    Rectangle().fill(Theme.muted.opacity(0.3)).frame(width: 14, height: 8).clipShape(RoundedRectangle(cornerRadius: 2))
                    Text("Shaded band is your own normal range")
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)
                }
            }
        }
    }

    /// A spoken-word summary of direction and range — Swift Charts marks aren't
    /// individually meaningful to VoiceOver, so the chart needs its own summary
    /// per the design doc's accessibility principle.
    private func trendSummary(_ points: [(Date, Double)]) -> String {
        guard let first = points.first?.1, let last = points.last?.1 else { return "" }
        let delta = last - first
        let direction = delta > 0.5 ? "up" : (delta < -0.5 ? "down" : "flat")
        let low = points.map(\.1).min() ?? 0
        let high = points.map(\.1).max() ?? 0
        return "Trending \(direction), ranging from \(Int(low)) to \(Int(high)) \(metric.unit)"
    }

    @ViewBuilder
    private var weekdayBreakdown: some View {
        let byWeekday = weekdayAverages()
        if !byWeekday.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow("By day of week")
                    Chart(byWeekday, id: \.weekday) { entry in
                        BarMark(x: .value("Day", entry.label), y: .value(metric.label, entry.average))
                            .foregroundStyle(Theme.vital.opacity(0.65))
                            .cornerRadius(3)
                    }
                    .chartXAxis {
                        AxisMarks { _ in AxisValueLabel().foregroundStyle(Theme.muted) }
                    }
                    .chartYAxis {
                        AxisMarks { _ in
                            AxisGridLine().foregroundStyle(Theme.stroke)
                            AxisValueLabel().foregroundStyle(Theme.muted)
                        }
                    }
                    .frame(height: 130)
                }
            }
        }
    }

    private func weekdayAverages() -> [(weekday: Int, label: String, average: Double)] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        var buckets: [Int: [Double]] = [:]
        for row in rows {
            guard let value = row.value(for: metric), let date = Self.dayFormatter.date(from: row.day) else { continue }
            buckets[calendar.component(.weekday, from: date), default: []].append(value)
        }
        let symbols = calendar.shortWeekdaySymbols
        return buckets.keys.sorted().compactMap { weekday in
            guard let mean = Stats.mean(buckets[weekday] ?? []) else { return nil }
            return (weekday, symbols[weekday - 1], mean)
        }
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        let sinceDay: String? = range.days.map { days in
            RecordDAO.dayString(for: Date().addingTimeInterval(-Double(days) * 86400))
        }
        let currentMetric = metric
        let loaded = try? await container.database.dbPool.read { db -> ([DailyMetricsRow], [String: (mean: Double, stddev: Double)]) in
            let metrics = try AnalysisQueries.dailyMetrics(db, sinceDay: sinceDay)
            let band = currentMetric.hasBaseline
                ? try AnalysisQueries.baselineBand(db, metric: currentMetric.columnName, sinceDay: sinceDay)
                : [:]
            return (metrics, band)
        }
        if let loaded {
            rows = loaded.0
            band = loaded.1
        }
    }

    /// `.task(id:)` needs one `Equatable` value, not two — bundles metric+range
    /// so a change to either one restarts the load.
    private struct Pair: Equatable {
        var metric: TrendMetric
        var range: RangeOption
        init(_ metric: TrendMetric, _ range: RangeOption) {
            self.metric = metric
            self.range = range
        }
    }
}
