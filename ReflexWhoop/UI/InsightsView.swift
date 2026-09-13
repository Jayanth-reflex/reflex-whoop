import SwiftUI

/// Ranked correlation cards and the anomaly timeline. Every card shows its own
/// confidence (rho, n, strength) rather than just a headline claim — per the
/// design doc, a dozen predictors tested on one person's data will always throw
/// up a spurious "finding" or two, and hiding the uncertainty would make this
/// screen actively misleading instead of just incomplete.
struct InsightsView: View {
    @Environment(AppContainer.self) private var container

    @State private var correlations: [CorrelationRow] = []
    @State private var anomalies: [AnomalyRow] = []
    @State private var isLoading = false

    private var findings: [CorrelationRow] { correlations.filter { $0.strengthEnum != .insufficient } }
    /// Whether anything rises above "weak" — drives whether this screen claims
    /// to have found something or admits it hasn't.
    private var hasRealFinding: Bool { findings.contains { $0.strengthEnum.rawValue != "weak" } }
    private var stillBuilding: [CorrelationRow] { correlations.filter { $0.strengthEnum == .insufficient } }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ink.ignoresSafeArea()
                if correlations.isEmpty && anomalies.isEmpty && !isLoading {
                    VStack(spacing: 8) {
                        Text("No patterns yet")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Theme.text)
                        Text("This needs about a month of days before it can tell signal from noise.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center)
                    }
                    .padding(40)
                } else {
                    List {
                        if !findings.isEmpty {
                            Section {
                                ForEach(findings) { CorrelationCard(row: $0) }
                            } header: {
                                Eyebrow(hasRealFinding ? "What moves your recovery" : "Nothing stands out yet")
                            } footer: {
                                // Every finding being weak is the honest, common
                                // result of testing a dozen predictors on one
                                // person. Saying so is the difference between an
                                // honest screen and one that dresses noise up as
                                // insight.
                                Text(hasRealFinding
                                     ? "Patterns in your own data. They show what moves together, which isn't proof that one causes the other."
                                     : "These are the closest things to a pattern so far, but none is strong enough to act on. That's normal — real signals take months to separate from noise.")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.muted)
                            }
                        }
                        if !stillBuilding.isEmpty {
                            Section {
                                ForEach(stillBuilding) { StillBuildingRow(row: $0) }
                            } header: {
                                Eyebrow("Not enough data yet")
                            }
                        }
                        if !anomalies.isEmpty {
                            Section {
                                ForEach(anomalies) { AnomalyTimelineRow(anomaly: $0) }
                            } header: {
                                Eyebrow("Unusual days")
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .listRowBackground(Theme.surface)
                }
            }
            .navigationTitle("Patterns")
            .toolbarBackground(Theme.ink, for: .navigationBar)
            .refreshable { await load() }
            .task { await load() }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let sinceDay = RecordDAO.dayString(for: Date().addingTimeInterval(-90 * 86400))
        let loaded = try? await container.database.dbPool.read { db -> ([CorrelationRow], [AnomalyRow]) in
            (try AnalysisQueries.correlations(db), try AnalysisQueries.anomalies(db, sinceDay: sinceDay))
        }
        if let loaded {
            correlations = loaded.0
            anomalies = loaded.1
        }
    }
}

/// Human-readable predictor names, shared by the card and "still building" row
/// so the two sections describe the same predictor identically.
enum PredictorLabel {
    static func label(_ predictor: String) -> String {
        switch predictor {
        case "prior_day_strain": "Yesterday's strain"
        case "respiratory_rate": "Respiratory rate"
        case "acute_chronic_ratio": "Training load balance (7d vs 28d)"
        case "sleep_duration_hours": "Sleep duration"
        case "sleep_efficiency_pct": "Sleep efficiency"
        case "sleep_consistency_pct": "Sleep consistency"
        case "rem_sleep_pct": "REM sleep share"
        case "slow_wave_sleep_pct": "Deep sleep share"
        case "sleep_disturbance_count": "Sleep disturbances"
        default: predictor
        }
    }
}

private struct CorrelationCard: View {
    let row: CorrelationRow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(sentence)
                .font(.subheadline)
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            // The statistics stay visible rather than being summarised away:
            // a dozen predictors tested against one person's data will always
            // produce a spurious finding or two, and hiding that would make
            // this screen misleading rather than merely incomplete.
            HStack(spacing: 6) {
                chip(row.strengthEnum.rawValue.capitalized, tint: strengthColor)
                chip("\(row.n) days")
                chip(String(format: "r %+.2f", row.rho))
                if let p = row.pValueBhCorrected {
                    chip(String(format: "p %.2f", p))
                }
            }
        }
        .padding(.vertical, 6)
        .listRowBackground(Theme.surface)
    }

    private var strengthColor: Color {
        switch row.strengthEnum.rawValue {
        case "strong": Theme.vital
        case "moderate": Theme.caution
        default: Theme.muted
        }
    }

    private var sentence: String {
        let name = PredictorLabel.label(row.predictor)
        let direction = row.rho > 0 ? "better" : "worse"
        return "More \(Self.sentenceCased(name)) tends to mean \(direction) recovery the next day."
    }

    /// Lowercases a label for mid-sentence use without destroying acronyms —
    /// naively lowercasing the first character turned "REM sleep share" into
    /// "rEM sleep share".
    private static func sentenceCased(_ name: String) -> String {
        guard let first = name.split(separator: " ").first else { return name }
        let isAcronym = first.count > 1 && first.allSatisfy { $0.isUppercase || !$0.isLetter }
        return isAcronym ? name : name.prefix(1).lowercased() + name.dropFirst()
    }

    private func chip(_ text: String, tint: Color = Theme.muted) -> some View {
        Text(text)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(tint)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

private struct StillBuildingRow: View {
    let row: CorrelationRow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(PredictorLabel.label(row.predictor))
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                Spacer()
                Text("\(row.n)/30")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.muted)
            }
            ProgressView(value: Double(min(row.n, 30)), total: 30)
                .tint(Theme.muted)
        }
        .padding(.vertical, 2)
        .listRowBackground(Theme.surface)
    }
}

private struct AnomalyTimelineRow: View {
    let anomaly: AnomalyRow

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(anomaly.kind == "illness_flag" ? Theme.alert : Theme.caution)
                .frame(width: 6, height: 6)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(anomaly.day)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.muted)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(Theme.surface)
    }

    private var text: String {
        if anomaly.kind == "illness_flag" {
            return "Breathing rate, skin temperature, resting heart rate and HRV all moved together — the pattern that often comes before illness."
        }
        if let metric = anomaly.metric, let z = anomaly.zScore {
            let label = TrendMetric(columnName: metric)?.label ?? metric
            return "\(label) was unusually \(z > 0 ? "high" : "low") for you."
        }
        return "Something was off from your normal."
    }
}
