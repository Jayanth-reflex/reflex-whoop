import XCTest
@testable import ReflexWhoop

final class BandTests: XCTestCase {
    func testRecoveryBandEdgesMatchWhoop() {
        XCTAssertEqual(RecoveryBand(score: 0), .low)
        XCTAssertEqual(RecoveryBand(score: 33), .low)
        XCTAssertEqual(RecoveryBand(score: 34), .moderate)
        XCTAssertEqual(RecoveryBand(score: 66), .moderate)
        XCTAssertEqual(RecoveryBand(score: 67), .high)
        XCTAssertEqual(RecoveryBand(score: 100), .high)
    }

    /// The zone strip draws each band from its bounds, so they must tile the scale.
    func testRecoveryBandsTileTheWholeScale() {
        let bands = RecoveryBand.allCases
        XCTAssertEqual(bands.first?.lowerBound, RecoveryBand.scale.lowerBound)
        XCTAssertEqual(bands.last?.upperBound, RecoveryBand.scale.upperBound)
        for (band, next) in zip(bands, bands.dropFirst()) {
            XCTAssertEqual(band.upperBound, next.lowerBound)
        }
    }

    func testStrainBandEdges() {
        XCTAssertEqual(StrainBand(strain: 0.5), .light)
        XCTAssertEqual(StrainBand(strain: 9.99), .light)
        XCTAssertEqual(StrainBand(strain: 10), .moderate)
        XCTAssertEqual(StrainBand(strain: 14), .high)
        XCTAssertEqual(StrainBand(strain: 18), .allOut)
        XCTAssertEqual(StrainBand.scaleMaximum, 21)
    }

    /// The verdict must not lean on sleep debt: the stored value is WHOOP's
    /// capped extra-need term, not debt owed.
    func testVerdictNeverMentionsSleepDebt() {
        for band in [RecoveryBand.low, .moderate, .high] {
            XCTAssertFalse(band.verdict.localizedStandardContains("debt"))
        }
    }
}
