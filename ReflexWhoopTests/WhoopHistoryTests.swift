import XCTest
import GRDB
@testable import ReflexWhoop

final class WhoopHistoryTests: XCTestCase {
    func testCountsWhatWhoopScoredNotJustRows() throws {
        let database = try TestSupport.makeDatabase()
        try database.dbPool.write { db in
            try db.execute(sql: """
                INSERT INTO daily_metrics (day, recovery_score, day_strain, algo_version, computed_at) VALUES
                ('2026-09-10', 80, 10.2, 1, 0),
                ('2026-09-11', NULL, 4.1, 1, 0),
                ('2026-09-12', 60, NULL, 1, 0)
                """)
            try db.execute(sql: """
                INSERT INTO sleeps (id, start, "end", nap, score_state, source) VALUES
                ('a', 1, 2, 0, 'SCORED', 'api'), ('b', 3, 4, 1, 'SCORED', 'api'), ('c', 5, 6, 0, 'SCORED', 'api')
                """)
        }
        let history = try database.dbPool.read(WhoopHistory.load)
        XCTAssertEqual(history, WhoopHistory(recoveryDays: 2, sleepNights: 2, strainDays: 2))
    }
}
