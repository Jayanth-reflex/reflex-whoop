import XCTest
@testable import ReflexWhoop

final class PatternsSummaryTests: XCTestCase {
    private func row(_ predictor: String, rho: Double, n: Int, p: Double?) -> CorrelationRow {
        CorrelationRow(
            predictor: predictor,
            outcome: CorrelationEngine.outcome,
            lagDays: 1,
            rho: rho,
            n: n,
            pValueBhCorrected: p,
            strength: Stats.strength(rho: rho, n: n).rawValue
        )
    }

    func testGroupsByStrengthStrongestFirst() {
        let summary = PatternsSummary(rows: [
            row("a", rho: 0.05, n: 64, p: 0.91),
            row("b", rho: -0.42, n: 64, p: 0.02),
            row("c", rho: -0.16, n: 64, p: 0.91),
            row("d", rho: 0.6, n: 12, p: nil),
            row("e", rho: 0.55, n: 64, p: 0.001),
        ])
        XCTAssertEqual(summary.findings.map(\.predictor), ["e", "b"])
        XCTAssertEqual(summary.weak.map(\.predictor), ["c", "a"])
        XCTAssertEqual(summary.building.map(\.predictor), ["d"])
        XCTAssertEqual(summary.comparedCount, 4)
        XCTAssertEqual(summary.dayCount, 64)
    }

    func testLowestPValueAmongTheWeak() {
        let summary = PatternsSummary(rows: [row("a", rho: 0.05, n: 64, p: 0.91), row("c", rho: -0.16, n: 64, p: 0.4)])
        XCTAssertTrue(summary.findings.isEmpty)
        XCTAssertEqual(summary.lowestWeakPValue, 0.4)
    }

    func testNothingComparedYet() {
        let summary = PatternsSummary(rows: [row("d", rho: 0.6, n: 12, p: nil)])
        XCTAssertEqual(summary.comparedCount, 0)
        XCTAssertEqual(summary.dayCount, 0)
        XCTAssertNil(summary.lowestWeakPValue)
    }
}
