import XCTest
@testable import ReflexWhoop

final class StatsTests: XCTestCase {
    func testMeanAndStddevAgainstHandComputedValues() {
        let xs = [2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0]
        XCTAssertEqual(Stats.mean(xs)!, 5.0, accuracy: 1e-9)
        // This textbook dataset's *population* stddev (divide by n) is exactly
        // 2.0 — but `Stats.stddev` deliberately computes *sample* stddev
        // (divide by n-1, see its doc comment), which is sqrt(32/7).
        XCTAssertEqual(Stats.stddev(xs)!, (32.0 / 7.0).squareRoot(), accuracy: 1e-9)
    }

    func testStddevRequiresAtLeastTwoValues() {
        XCTAssertNil(Stats.stddev([5.0]))
        XCTAssertNil(Stats.stddev([]))
    }

    func testZScore() {
        XCTAssertEqual(Stats.zScore(value: 65, mean: 50, stddev: 10)!, 1.5, accuracy: 1e-9)
        XCTAssertNil(Stats.zScore(value: 65, mean: 50, stddev: 0), "zero stddev must not divide by zero")
    }

    func testSpearmanRhoIsOneForPerfectMonotonicIncrease() {
        let xs = [1.0, 2, 3, 4, 5, 6, 7, 8]
        let ys = [10.0, 20, 30, 40, 50, 60, 70, 80]
        let (rho, n) = Stats.spearmanRho(xs, ys)!
        XCTAssertEqual(rho, 1.0, accuracy: 1e-9)
        XCTAssertEqual(n, 8)
    }

    func testSpearmanRhoIsMinusOneForPerfectMonotonicDecrease() {
        let xs = [1.0, 2, 3, 4, 5]
        let ys = [50.0, 40, 30, 20, 10]
        let (rho, _) = Stats.spearmanRho(xs, ys)!
        XCTAssertEqual(rho, -1.0, accuracy: 1e-9)
    }

    func testSpearmanRhoHandlesTiesWithoutCrashing() {
        let xs = [1.0, 1, 1, 2, 2, 3]
        let ys = [1.0, 2, 3, 1, 2, 3]
        XCTAssertNotNil(Stats.spearmanRho(xs, ys))
    }

    func testSpearmanRhoRequiresAtLeastThreePairs() {
        XCTAssertNil(Stats.spearmanRho([1, 2], [1, 2]))
    }

    func testPValueIsSmallForStrongCorrelationWithDecentSampleSize() {
        // rho = 0.7 over n = 40 is a real, unmistakable relationship.
        let p = Stats.pValue(rho: 0.7, n: 40)!
        XCTAssertLessThan(p, 0.001)
    }

    func testPValueIsLargeForZeroCorrelation() {
        let p = Stats.pValue(rho: 0.0, n: 40)!
        XCTAssertEqual(p, 1.0, accuracy: 1e-9)
    }

    func testPValueGrowsAsSampleSizeShrinks() {
        // The same rho is much less trustworthy with fewer observations —
        // p-value must reflect that even though rho itself doesn't change.
        let pLargeN = Stats.pValue(rho: 0.3, n: 200)!
        let pSmallN = Stats.pValue(rho: 0.3, n: 10)!
        XCTAssertLessThan(pLargeN, pSmallN)
    }

    func testBenjaminiHochbergNeverMakesAPValueSmaller() {
        let raw = [0.001, 0.01, 0.03, 0.2, 0.5]
        let corrected = Stats.benjaminiHochberg(raw)
        for i in raw.indices {
            XCTAssertGreaterThanOrEqual(corrected[i], raw[i] - 1e-12)
        }
    }

    func testBenjaminiHochbergPreservesRankOrder() {
        // A stronger raw finding must never end up with a worse corrected
        // p-value than a weaker one in the same batch.
        let raw = [0.001, 0.04, 0.3]
        let corrected = Stats.benjaminiHochberg(raw)
        XCTAssertLessThanOrEqual(corrected[0], corrected[1])
        XCTAssertLessThanOrEqual(corrected[1], corrected[2])
    }

    func testStrengthIsInsufficientBelowThirtySamples() {
        XCTAssertEqual(Stats.strength(rho: 0.9, n: 29), .insufficient)
        XCTAssertNotEqual(Stats.strength(rho: 0.9, n: 30), .insufficient)
    }

    func testStrengthBands() {
        XCTAssertEqual(Stats.strength(rho: 0.6, n: 100), .strong)
        XCTAssertEqual(Stats.strength(rho: 0.35, n: 100), .moderate)
        XCTAssertEqual(Stats.strength(rho: 0.15, n: 100), .weak)
        XCTAssertEqual(Stats.strength(rho: -0.6, n: 100), .strong, "strength is about magnitude, sign-independent")
    }
}
