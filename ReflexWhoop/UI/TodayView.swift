import SwiftUI
import GRDB

/// The one screen that answers "what should I do today." Everything here is
/// arranged around that sentence: the verdict is the hero, the recovery ring
/// and metric strip are evidence for it, and each number carries its own
/// confidence rather than implying certainty it doesn't have.
struct TodayView: View {
    @Environment(AppContainer.self) private var container

    @State private var showingSettings = false
    @State private var snapshot: Snapshot?
    @State private var isLoading = false

    private struct Snapshot {
        var metrics: DailyMetricsRow?
        var anomalies: [AnomalyRow]
        var sleep: LatestSleepDetail?
        var lastSyncedAt: Date?
        var sources: AppContainer.SourceSnapshot?
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ink.ignoresSafeArea()
                content
            }
            .navigationTitle("Today")
            .toolbarBackground(Theme.ink, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .tint(Theme.muted)
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .refreshable { await load() }
            .task { await load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        // Being signed out is only an empty state when there is genuinely
        // nothing to show. With history on disk it is a banner over real data.
        if !container.isSignedIn, snapshot?.sources?.archive.isEmpty ?? true {
            emptyState
        } else if let snapshot, let metrics = snapshot.metrics {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.gutter) {
                    if let sources = snapshot.sources, !sources.whoop.canCollect {
                        archiveBanner(sources)
                    }
                    verdict(metrics, anomalies: snapshot.anomalies)
                    vitals(metrics)
                    if let sleep = snapshot.sleep {
                        sleepCard(metrics, sleep: sleep)
                    }
                    if !snapshot.anomalies.isEmpty {
                        anomalyCard(snapshot.anomalies)
                    }
                    statusStrip(snapshot)
                }
                .padding(Theme.gutter)
            }
        } else if isLoading {
            ProgressView().tint(Theme.muted)
        } else {
            noDataState
        }
    }

    // MARK: - Empty states

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.vital)
            Text("Nothing collected yet")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.text)
            Text("Connect your WHOOP account to pull your history, or record from the band on the Live tab.")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            Button("Open settings") { showingSettings = true }
                .buttonStyle(.borderedProminent)
                .tint(Theme.vital)
                .foregroundStyle(Theme.ink)
                .padding(.top, 4)
        }
        .padding(40)
    }

    private var noDataState: some View {
        VStack(spacing: 10) {
            Text("No scores for today yet")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.text)
            Text("Pull down to sync.")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
        }
        .padding(40)
    }

    // MARK: - Hero

    /// The signature element: the day's answer, set large, with a rule in the
    /// recovery band's own color. The color is never the only carrier — the
    /// sentence says the same thing in words.
    private func verdict(_ m: DailyMetricsRow, anomalies: [AnomalyRow]) -> some View {
        let band = m.recoveryScore?.recoveryBand
        return VStack(alignment: .leading, spacing: 12) {
            Eyebrow("The read", tint: band?.color ?? Theme.muted)
            Text(verdictText(m, anomalies: anomalies))
                .font(.system(size: 27, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
            Rectangle()
                .fill(band?.color ?? Theme.stroke)
                .frame(width: 56, height: 3)
                .clipShape(Capsule())
        }
    }

    private func verdictText(_ m: DailyMetricsRow, anomalies: [AnomalyRow]) -> String {
        guard let recovery = m.recoveryScore else {
            return "Today's recovery hasn't arrived yet."
        }
        let band = recovery.recoveryBand
        var sentence: String
        switch band.label {
        case "High": sentence = "You're recovered. Good day to push."
        case "Moderate": sentence = "Middling recovery. Train, but leave something in reserve."
        default: sentence = "Low recovery. Go easy today."
        }
        if let debtMilli = m.sleepDebtMilli, debtMilli > 0 {
            let hours = debtMilli / 3_600_000
            let minutes = (debtMilli % 3_600_000) / 60_000
            sentence += hours > 0 ? " You're \(hours)h \(minutes)m down on sleep." : " You're \(minutes)m down on sleep."
        }
        if anomalies.contains(where: { $0.kind == "illness_flag" }) {
            sentence += " Several signals are off from your normal."
        }
        return sentence
    }

    // MARK: - Vitals

    private func vitals(_ m: DailyMetricsRow) -> some View {
        Card {
            HStack(alignment: .center, spacing: Theme.cardPadding) {
                recoveryRing(m)
                VStack(alignment: .leading, spacing: 18) {
                    Readout(
                        label: "Strain",
                        value: m.dayStrain.map { String(format: "%.1f", $0) },
                        note: m.dayStrain.map(strainBand),
                        size: 24
                    )
                    Readout(
                        label: "Readiness",
                        value: m.readinessScore.map { "\(Int($0))" },
                        note: m.readinessScore == nil ? "Not enough history" : "This app's score, not WHOOP's",
                        size: 24
                    )
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func recoveryRing(_ m: DailyMetricsRow) -> some View {
        let recovery = m.recoveryScore
        let band = recovery?.recoveryBand
        return ZStack {
            Circle().stroke(Theme.stroke, lineWidth: 8)
            if let recovery, let band {
                Circle()
                    .trim(from: 0, to: recovery / 100)
                    .stroke(band.color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(Int(recovery))")
                        .font(Theme.readout(34))
                        .foregroundStyle(Theme.text)
                    Text(band.label)
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(band.color)
                }
            } else {
                Text("—").font(Theme.readout(30)).foregroundStyle(Theme.muted)
            }
        }
        .frame(width: 108, height: 108)
        // The ring's meaning never depends on color alone — the number and the
        // band name are both present for a color-blind reader.
        .accessibilityElement()
        .accessibilityLabel(recovery.map { "Recovery \(Int($0)) percent, \($0.recoveryBand.label)" } ?? "Recovery unavailable")
    }

    // MARK: - Cards

    private func archiveBanner(_ sources: AppContainer.SourceSnapshot) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow("WHOOP \(sources.whoop.label)", tint: Theme.caution)
                if let detail = sources.whoop.detail {
                    Text(detail).font(.footnote).foregroundStyle(Theme.text)
                }
                if let first = sources.archive.firstDay, let last = sources.archive.lastDay {
                    Text("Your \(sources.archive.dayCount) days from \(first) to \(last) are stored on this phone. Everything below is computed from them.")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
            }
        }
    }

    private func sleepCard(_ m: DailyMetricsRow, sleep: LatestSleepDetail) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Eyebrow("Last night")
                    Spacer()
                    Text(String(format: "%.1fh", sleep.durationHours))
                        .font(Theme.readout(20))
                        .foregroundStyle(Theme.text)
                    if let perf = m.sleepPerformancePercentage {
                        Text("· \(Int(perf))%")
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                    }
                }
                sleepStageBar(sleep)
                stageLegend(sleep)
            }
        }
    }

    private func stageSegments(_ sleep: LatestSleepDetail) -> [(String, Int64, Color)] {
        [
            ("REM", sleep.remMs ?? 0, Theme.vital.opacity(0.85)),
            ("Deep", sleep.swsMs ?? 0, Color(red: 0.40, green: 0.53, blue: 1.0)),
            ("Light", sleep.lightMs ?? 0, Color(red: 0.25, green: 0.33, blue: 0.50)),
            ("Awake", sleep.awakeMs ?? 0, Theme.caution.opacity(0.8)),
        ]
    }

    private func sleepStageBar(_ sleep: LatestSleepDetail) -> some View {
        let segments = stageSegments(sleep)
        let total = max(segments.reduce(0) { $0 + $1.1 }, 1)
        return GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(segments, id: \.0) { segment in
                    segment.2.frame(width: max(0, geo.size.width * CGFloat(segment.1) / CGFloat(total) - 2))
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 8)
        .accessibilityElement()
        .accessibilityLabel(segments.map { "\($0.0) \(Int(Double($0.1) / Double(total) * 100)) percent" }.joined(separator: ", "))
    }

    private func stageLegend(_ sleep: LatestSleepDetail) -> some View {
        let segments = stageSegments(sleep)
        let total = max(segments.reduce(0) { $0 + $1.1 }, 1)
        return HStack(spacing: 14) {
            ForEach(segments, id: \.0) { segment in
                HStack(spacing: 5) {
                    Circle().fill(segment.2).frame(width: 6, height: 6)
                    Text(segment.0).font(.caption2).foregroundStyle(Theme.muted)
                    Text("\(Int(Double(segment.1) / Double(total) * 100))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Theme.text)
                }
            }
        }
        .accessibilityHidden(true) // the bar above already reads this out
    }

    private func anomalyCard(_ anomalies: [AnomalyRow]) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow("Worth noting", tint: Theme.caution)
                ForEach(anomalies) { anomaly in
                    Text(anomalyText(anomaly))
                        .font(.subheadline)
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func anomalyText(_ anomaly: AnomalyRow) -> String {
        if anomaly.kind == "illness_flag" {
            return "Breathing rate, skin temperature, resting heart rate and HRV are all moving the way they usually do before you come down with something."
        }
        if let metric = anomaly.metric, let z = anomaly.zScore {
            let label = TrendMetric(columnName: metric)?.label ?? metric
            return "\(label) is unusually \(z > 0 ? "high" : "low") for you today."
        }
        return "Something is off from your normal today."
    }

    private func statusStrip(_ snapshot: Snapshot) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(snapshot.lastSyncedAt == nil ? Theme.muted : Theme.vital)
                .frame(width: 5, height: 5)
            if let lastSync = snapshot.lastSyncedAt {
                Text("Synced \(lastSync.formatted(.relative(presentation: .named)))")
            } else {
                Text("Not synced yet")
            }
        }
        .font(.caption)
        .foregroundStyle(Theme.muted)
        .frame(maxWidth: .infinity)
    }

    private func strainBand(_ strain: Double) -> String {
        switch strain {
        case ..<10: "Light day"
        case 10..<14: "Moderate day"
        case 14..<18: "Hard day"
        default: "All out"
        }
    }

    // MARK: - Loading

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let today = RecordDAO.dayString(for: Date())
        let sources = await container.sourceSnapshot()
        let loaded = try? await container.database.dbPool.read { db -> Snapshot in
            Snapshot(
                metrics: try AnalysisQueries.latestDailyMetrics(db),
                anomalies: try AnalysisQueries.anomalies(db, day: today),
                sleep: try AnalysisQueries.latestSleepDetail(db),
                lastSyncedAt: try AnalysisQueries.lastSyncedAt(db),
                sources: sources
            )
        }
        if let loaded {
            snapshot = loaded
        }
    }
}
