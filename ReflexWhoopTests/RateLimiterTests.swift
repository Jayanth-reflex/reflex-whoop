import XCTest
@testable import ReflexWhoop

final class RateLimiterTests: XCTestCase {
    func testAcquireDoesNotBlockUnderCapacity() async {
        let limiter = RateLimiter(minuteCapacity: 10, dailyCapacity: 1000)
        let start = Date()
        for _ in 0..<10 {
            await limiter.acquire()
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.0, "should not wait while under capacity")
    }

    func testAcquireBlocksOnceMinuteCapacityExhausted() async {
        let limiter = RateLimiter(minuteCapacity: 2, dailyCapacity: 1000)
        await limiter.acquire()
        await limiter.acquire()

        let flag = CompletionFlag()
        // Deliberately not awaited or cancelled: it will genuinely sleep for up to
        // 60s (real wall-clock window, no injectable clock) and either complete in
        // the background or get torn down when the test process exits — either
        // way harmless, since it's a real sleep, not a busy-loop.
        Task {
            await limiter.acquire()
            await flag.set()
        }

        try? await Task.sleep(nanoseconds: 200_000_000)
        let completedEarly = await flag.value
        XCTAssertFalse(completedEarly, "acquire() must block once minute capacity is exhausted")
    }

    func testRecordHeadersTightensEstimateUpwardOnly() async {
        let limiter = RateLimiter(minuteCapacity: 100, dailyCapacity: 10000)
        await limiter.acquire() // local count = 1

        // Server says only 5 remain (95 used) — local estimate must jump up to match.
        await limiter.recordHeaders(remaining: 5, resetSeconds: 30)
        let countAfterTighten = await limiter.currentMinuteCountForTesting()
        XCTAssertEqual(countAfterTighten, 95)

        // A looser server value must never lower our estimate below what we already
        // know locally (protects against exceeding the real limit on stale data).
        await limiter.recordHeaders(remaining: 90, resetSeconds: 30)
        let countAfterLooserHeader = await limiter.currentMinuteCountForTesting()
        XCTAssertEqual(countAfterLooserHeader, 95, "a looser header must not relax an already-tighter local estimate")
    }
}

private actor CompletionFlag {
    private(set) var value = false
    func set() { value = true }
}
