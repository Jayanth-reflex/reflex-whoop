import XCTest
@testable import ReflexWhoop

/// Opening the app started a foreground sync from two places at once, and "pull" and
/// "manual" could land in the same second too; each built its own engine, so nothing
/// knew another was running. Three overlapping syncs on 26 September each tried to
/// refresh the WHOOP token, and the stored token didn't survive it. Every sync now goes
/// through one runner: a sync that starts while another is running joins it.
final class SyncRunnerTests: XCTestCase {
    private actor Counter {
        private(set) var runs = 0
        func increment() -> Int { runs += 1; return runs }
    }

    func testOverlappingSyncsRunOnceAndShareTheResult() async throws {
        let runner = SyncRunner()
        let counter = Counter()

        let summaries = try await withThrowingTaskGroup(of: ApiSyncEngine.Summary.self) { group in
            for _ in 0..<3 {
                group.addTask {
                    try await runner.run {
                        let run = await counter.increment()
                        try await Task.sleep(for: .milliseconds(200))
                        return ApiSyncEngine.Summary(requestsMade: run, recordsUpserted: 0, error: nil)
                    }
                }
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }

        let runs = await counter.runs
        XCTAssertEqual(runs, 1)
        XCTAssertEqual(summaries.map(\.requestsMade), [1, 1, 1])
    }

    func testASyncAfterTheLastOneFinishedRunsAgain() async throws {
        let runner = SyncRunner()
        let counter = Counter()
        for _ in 0..<2 {
            _ = try await runner.run {
                ApiSyncEngine.Summary(requestsMade: await counter.increment(), recordsUpserted: 0, error: nil)
            }
        }
        let runs = await counter.runs
        XCTAssertEqual(runs, 2)
    }

    /// A failed sync must not be remembered as the answer to the next one.
    func testAFailedSyncDoesNotBlockTheNext() async throws {
        struct Offline: Error {}
        let runner = SyncRunner()
        do {
            _ = try await runner.run { throw Offline() }
            XCTFail("expected the failure to surface")
        } catch is Offline {}

        let summary = try await runner.run { ApiSyncEngine.Summary(requestsMade: 7, recordsUpserted: 0, error: nil) }
        XCTAssertEqual(summary.requestsMade, 7)
    }
}
