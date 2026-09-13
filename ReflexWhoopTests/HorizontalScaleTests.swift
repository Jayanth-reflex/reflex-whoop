import XCTest
@testable import ReflexWhoop

final class HorizontalScaleTests: XCTestCase {
    private let scale = HorizontalScale(domain: 0...100, inset: 10, width: 220)

    func testEndsSitInsideTheInset() {
        XCTAssertEqual(scale.x(0), 10)
        XCTAssertEqual(scale.x(100), 210)
        XCTAssertEqual(scale.x(50), 110)
    }

    func testValuesOutsideTheDomainAreHeldAtTheEnds() {
        XCTAssertEqual(scale.position(-20), 0)
        XCTAssertEqual(scale.position(140), 1)
        XCTAssertEqual(scale.x(140), 210)
    }

    func testEmptyDomainDoesNotDivideByZero() {
        let flat = HorizontalScale(domain: 5...5, inset: 0, width: 100)
        XCTAssertEqual(flat.position(5), 0)
    }
}
