import XCTest
@testable import ReflexWhoop

final class ContinuousRunsTests: XCTestCase {
    private func at(_ minute: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(minute * 60)) }

    func testEmptyInputHasNoRuns() {
        XCTAssertTrue(ContinuousRuns.split([Date](), maximumGap: 60, time: { $0 }).isEmpty)
    }

    func testBreaksOnlyWhereTheGapExceedsTheMaximum() {
        let times = [0, 1, 2, 10, 11, 30].map(at)
        let runs = ContinuousRuns.split(times, maximumGap: 180, time: { $0 })
        XCTAssertEqual(runs.map(\.count), [3, 2, 1])
    }

    func testGapEqualToMaximumStaysJoined() {
        XCTAssertEqual(ContinuousRuns.split([at(0), at(3)], maximumGap: 180, time: { $0 }).count, 1)
    }
}
