import XCTest
@testable import ReflexWhoop

final class ChartDomainTests: XCTestCase {
    func testNoValuesHaveNoDomain() {
        XCTAssertNil(ChartDomain.padded([Double]()))
        XCTAssertNil(ChartDomain.padded([MetricPoint]()))
    }

    func testPadsBothEndsByAFractionOfTheSpan() {
        XCTAssertEqual(ChartDomain.padded([50, 150], fraction: 0.25), 25...175)
    }

    func testEqualValuesStillGetARange() {
        XCTAssertEqual(ChartDomain.padded([60, 60]), 59...61)
    }

    /// The normal band has to fit even when every reading sits inside it.
    func testMetricDomainIncludesTheNormalBand() throws {
        let date = Date(timeIntervalSince1970: 0)
        let points = [MetricPoint(day: "1970-01-01", date: date, value: 60, range: NormalRange(mean: 60, standardDeviation: 10))]
        let domain = try XCTUnwrap(ChartDomain.padded(points, fraction: 0))
        XCTAssertEqual(domain, 50...70)
    }
}
