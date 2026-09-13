import Foundation
import GRDB

/// How much WHOOP has scored, by kind, for the account screen.
struct WhoopHistory: Equatable {
    let recoveryDays: Int
    let sleepNights: Int
    let strainDays: Int

    static func load(_ db: GRDB.Database) throws -> WhoopHistory {
        let row = try Row.fetchOne(
            db,
            sql: """
            SELECT
                (SELECT COUNT(*) FROM daily_metrics WHERE recovery_score IS NOT NULL) AS recovery_days,
                (SELECT COUNT(*) FROM sleeps WHERE nap = 0) AS sleep_nights,
                (SELECT COUNT(*) FROM daily_metrics WHERE day_strain IS NOT NULL) AS strain_days
            """
        )
        return WhoopHistory(
            recoveryDays: row?["recovery_days"] ?? 0,
            sleepNights: row?["sleep_nights"] ?? 0,
            strainDays: row?["strain_days"] ?? 0
        )
    }
}
