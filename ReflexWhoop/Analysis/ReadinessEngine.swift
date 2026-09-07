import Foundation
import GRDB

/// ReflexWhoop's own composite readiness score — HRV z, RHR z, sleep-debt, and
/// training-load balance, blended into one 0-100 number. This is deliberately
/// NOT a reproduction of WHOOP's recovery score: it's built from the same raw
/// signal, but the weighting and the sleep-debt/load-balance heuristics below
/// are ours, and every surface that shows it must label it "ReflexWhoop score —
/// not WHOOP's" per the design doc.
enum ReadinessEngine {
    static let algoVersion = 1

    /// A day's debt fully offsetting the score at 2 hours is a simplification —
    /// the technically-correct version scales debt against that night's own
    /// personalized sleep-need baseline (`sleep_need.baseline_milli`), which
    /// would need an extra join per day. Fixed-scale is honest about being a
    /// heuristic and cheap; revisit if it turns out to feel wrong in practice.
    private static let fullDebtOffsetMilli: Double = 2 * 3600 * 1000

    private static let acuteWindow = 7
    private static let chronicWindow = 28
    private static let minimumChronicSample = 14

    static func compute(_ db: GRDB.Database, day: String) throws {
        var components: [Double] = []

        if let hrvZ = try BaselineEngine.zScore(db, metric: "hrv_rmssd_milli", day: day) {
            components.append(squash(hrvZ))
        }
        if let rhrZ = try BaselineEngine.zScore(db, metric: "resting_heart_rate", day: day) {
            // Lower resting heart rate than your own baseline is the good
            // direction, so the z-score's sign is flipped before squashing.
            components.append(squash(-rhrZ))
        }
        if let debtMilli = try Double.fetchOne(db, sql: "SELECT sleep_debt_milli FROM daily_metrics WHERE day = ?", arguments: [day]) {
            let debtScore = 100 * (1 - min(max(debtMilli / fullDebtOffsetMilli, 0), 1))
            components.append(debtScore)
        }
        if let loadScore = try loadBalanceScore(db, day: day) {
            components.append(loadScore)
        }

        // Fewer than half the possible signals present — a 1-component "average"
        // is just that one number wearing a costume. Leave readiness NULL.
        guard components.count >= 2 else { return }

        let readiness = Stats.mean(components)
        try db.execute(
            sql: "UPDATE daily_metrics SET readiness_score = ? WHERE day = ?",
            arguments: [readiness, day]
        )
    }

    /// Maps a z-score to a 0-100 scale centered on 50 ("exactly your own
    /// normal"). ±2 SD lands near the ends (20/80) rather than the extremes,
    /// since a single day 2 SD out is notable but not "everything is broken."
    private static func squash(_ z: Double) -> Double {
        min(max(50 + z * 15, 0), 100)
    }

    /// Acute:chronic training-load ratio (7-day vs 28-day trailing average
    /// strain, both including today) — the same ACWR heuristic used in the
    /// design doc's "load balance" trend, reused here as a readiness input.
    /// Scored as distance from 1.0 (perfectly balanced), not as "more is worse":
    /// both overreaching (ratio > 1) and detraining (ratio < 1) cost points.
    private static func loadBalanceScore(_ db: GRDB.Database, day: String) throws -> Double? {
        let acute = try Double.fetchAll(
            db, sql: "SELECT day_strain FROM daily_metrics WHERE day <= ? AND day_strain IS NOT NULL ORDER BY day DESC LIMIT ?",
            arguments: [day, acuteWindow]
        )
        let chronic = try Double.fetchAll(
            db, sql: "SELECT day_strain FROM daily_metrics WHERE day <= ? AND day_strain IS NOT NULL ORDER BY day DESC LIMIT ?",
            arguments: [day, chronicWindow]
        )
        guard chronic.count >= minimumChronicSample,
              let acuteMean = Stats.mean(acute), let chronicMean = Stats.mean(chronic), chronicMean > 0 else {
            return nil
        }
        let ratio = acuteMean / chronicMean
        return 100 * (1 - min(abs(ratio - 1.0), 1.0))
    }
}
