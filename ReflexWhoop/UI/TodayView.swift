import SwiftUI
import GRDB

/// Per the design doc's UI principles: one sentence at the top answers "what
/// should I do today," the ring is supporting evidence not the message, and
/// every number states its own confidence rather than implying certainty it
/// doesn't have.
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
            Group {
                // Archive mode: a source that can no longer collect does not
                // take the screen down with it. Only an empty archive gets the
                // "nothing here" treatment — with 438 days on disk, being
                // signed out is a banner, not a blank page.
                // docs/ADR-001-data-sovereignty.md.
                if !container.isSignedIn, snapshot?.sources?.archive.isEmpty ?? true {
                    ContentUnavailableView(
                        "Not connected yet",
                        systemImage: "bolt.horizontal.circle",
                        description: Text("Connect your WHOOP account in Settings to start collecting data.")
                    )
                } else if let snapshot, snapshot.metrics != nil {
                    content(snapshot)
                } else if isLoading {
                    ProgressView()
                } else {
                    ContentUnavailableView(
                        "No data yet",
                        systemImage: "arrow.triangle.2.circlepath",
                        description: Text("Pull to sync, or check Settings if this doesn't clear up.")
                    )
                }
            }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .refreshable { await load() }
            .task { await load() }
        }
    }

    @ViewBuilder
    private func content(_ snapshot: Snapshot) -> some View {
        let metrics = snapshot.metrics! // guarded by the caller above
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let sources = snapshot.sources, !sources.whoop.canCollect {
                    archiveBanner(sources)
                }

                verdict(metrics, anomalies: snapshot.anomalies)

                HStack(spacing: 16) {
                    recoveryRing(metrics)
                    VStack(alignment: .leading, spacing: 12) {
                        strainRow(metrics)
                        readinessRow(metrics)
                    }
                }

                if let sleep = snapshot.sleep {
                    sleepCard(metrics, sleep: sleep)
                }

                if !snapshot.anomalies.isEmpty {
                    anomalyCard(snapshot.anomalies)
                }

                statusStrip(snapshot)
            }
            .padding()
        }
    }

    // MARK: - Sections

    /// Shown when WHOOP can no longer collect. States what still works rather
    /// than what broke: the analysis below is computed entirely from the local
    /// archive and stays correct whether or not another byte ever arrives.
    private func archiveBanner(_ sources: AppContainer.SourceSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("WHOOP source \(sources.whoop.label.lowercased())", systemImage: "archivebox")
                .font(.subheadline.weight(.semibold))
            if let detail = sources.whoop.detail {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            if let first = sources.archive.firstDay, let last = sources.archive.lastDay {
                Text("Archive: \(sources.archive.dayCount) days, \(first) to \(last). Everything below is computed from it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func verdict(_ m: DailyMetricsRow, anomalies: [AnomalyRow]) -> some View {
        Text(verdictText(m, anomalies: anomalies))
            .font(.title3.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func verdictText(_ m: DailyMetricsRow, anomalies: [AnomalyRow]) -> String {
        guard let recovery = m.recoveryScore else {
            return "Recovery hasn't synced yet today."
        }
        let band = recoveryBand(recovery)
        var sentence = "Recovery \(Int(recovery))% — \(band.label.lowercased())."

        if let debtMilli = m.sleepDebtMilli, debtMilli > 0 {
            let hours = debtMilli / 3_600_000
            let minutes = (debtMilli % 3_600_000) / 60_000
            sentence += " Sleep debt is \(hours)h \(minutes)m."
        }
        if anomalies.contains(where: { $0.kind == "illness_flag" }) {
            sentence += " Several signals are off from your normal — worth keeping an eye on."
        }
        return sentence
    }

    private func recoveryRing(_ m: DailyMetricsRow) -> some View {
        let recovery = m.recoveryScore
        let band = recovery.map(recoveryBand)
        return ZStack {
            Circle().stroke(.quaternary, lineWidth: 10)
            if let recovery {
                Circle()
                    .trim(from: 0, to: recovery / 100)
                    .stroke(band!.color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text("\(Int(recovery))%").font(.title.bold())
                    Text(band!.label).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("—").font(.title.bold()).foregroundStyle(.secondary)
            }
        }
        .frame(width: 120, height: 120)
        // Never color-only: label and percentage both carry the same
        // information the ring color does, for color-blind readers.
        .accessibilityLabel(recovery.map { "Recovery \(Int($0)) percent, \(band!.label)" } ?? "Recovery not available")
    }

    private func strainRow(_ m: DailyMetricsRow) -> some View {
        HStack {
            Label("Strain", systemImage: "flame")
            Spacer()
            if let strain = m.dayStrain {
                Text(String(format: "%.1f", strain)).bold()
                Text(strainBand(strain)).font(.caption).foregroundStyle(.secondary)
            } else {
                Text("—").foregroundStyle(.secondary)
            }
        }
    }

    private func readinessRow(_ m: DailyMetricsRow) -> some View {
        HStack {
            Label("Readiness", systemImage: "gauge.with.dots.needle.50percent")
            Spacer()
            if let readiness = m.readinessScore {
                Text("\(Int(readiness))").bold()
            } else {
                Text("insufficient data").font(.caption).foregroundStyle(.secondary)
            }
        }
        // Labeled every place it appears, per the design doc — this is not WHOOP's number.
        .overlay(alignment: .bottomLeading) {
            Text("ReflexWhoop score — not WHOOP's")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .offset(y: 16)
        }
        .padding(.bottom, 12)
    }

    private func sleepCard(_ m: DailyMetricsRow, sleep: LatestSleepDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Last night", systemImage: "moon.stars")
                Spacer()
                if let perf = m.sleepPerformancePercentage {
                    Text("\(Int(perf))%").bold()
                }
            }
            Text(String(format: "%.1fh", sleep.durationHours)).font(.caption).foregroundStyle(.secondary)
            sleepStageBar(sleep)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func sleepStageBar(_ sleep: LatestSleepDetail) -> some View {
        let segments: [(String, Int64, Color)] = [
            ("REM", sleep.remMs ?? 0, .cyan),
            ("Deep", sleep.swsMs ?? 0, .indigo),
            ("Light", sleep.lightMs ?? 0, .blue.opacity(0.5)),
            ("Awake", sleep.awakeMs ?? 0, .orange),
        ]
        let total = max(segments.reduce(0) { $0 + $1.1 }, 1)
        return GeometryReader { geo in
            HStack(spacing: 1) {
                ForEach(segments, id: \.0) { segment in
                    Color(segment.2)
                        .frame(width: geo.size.width * CGFloat(segment.1) / CGFloat(total))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .frame(height: 10)
        .accessibilityElement()
        .accessibilityLabel(sleepStageAccessibilityLabel(segments, total: total))
    }

    private func sleepStageAccessibilityLabel(_ segments: [(String, Int64, Color)], total: Int64) -> String {
        segments.map { "\($0.0) \(Int(Double($0.1) / Double(total) * 100))%" }.joined(separator: ", ")
    }

    private func anomalyCard(_ anomalies: [AnomalyRow]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Worth noting today", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.yellow)
            ForEach(anomalies) { anomaly in
                Text(anomalyText(anomaly)).font(.subheadline)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func anomalyText(_ anomaly: AnomalyRow) -> String {
        if anomaly.kind == "illness_flag" {
            return "Respiratory rate, skin temp, resting HR, and HRV are moving together in the direction that usually means you're coming down with something."
        }
        if let metric = anomaly.metric, let z = anomaly.zScore {
            let direction = z > 0 ? "higher" : "lower"
            let label = TrendMetric(columnName: metric)?.label ?? metric
            return "\(label) is unusually \(direction) than your normal today."
        }
        return "Unusual reading today."
    }

    private func statusStrip(_ snapshot: Snapshot) -> some View {
        HStack {
            Image(systemName: "checkmark.icloud")
            if let lastSync = snapshot.lastSyncedAt {
                Text("Synced \(lastSync.formatted(.relative(presentation: .named)))")
            } else {
                Text("Not synced yet")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    // MARK: - Bands

    private func recoveryBand(_ score: Double) -> (label: String, color: Color) {
        switch score {
        case 67...: ("Good recovery", .green)
        case 34..<67: ("Adequate recovery", .yellow)
        default: ("Low recovery", .red)
        }
    }

    private func strainBand(_ strain: Double) -> String {
        switch strain {
        case ..<10: "Light"
        case 10..<14: "Moderate"
        case 14..<18: "Strenuous"
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
