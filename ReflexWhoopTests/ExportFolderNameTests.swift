import XCTest
@testable import ReflexWhoop

final class ExportFolderNameTests: XCTestCase {
    /// Readable in Files, sorts by time, and has no colons (Finder shows them as slashes).
    func testFolderNameIsLocalSortableAndColonFree() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-13T19:53:31Z"))
        let india = try XCTUnwrap(TimeZone(identifier: "Asia/Kolkata"))
        XCTAssertEqual(Exporter.folderName(for: date, timeZone: india), "2026-09-14 at 01.23.31")
    }
}
