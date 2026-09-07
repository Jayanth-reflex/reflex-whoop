import Foundation

/// Client-side token bucket kept under WHOOP's documented limits (100 req/min,
/// 10 000 req/day), with headroom so a burst of concurrent requests never
/// actually reaches the server-side 429 threshold. Self-corrects from
/// `X-RateLimit-*` response headers when present, since those are ground truth
/// and our local counters are only an estimate (a killed-and-relaunched app
/// resets to zero locally while WHOOP's server-side window keeps counting).
actor RateLimiter {
    private let minuteCapacity: Int
    private let dailyCapacity: Int

    private var minuteCount = 0
    private var minuteWindowStart = Date()
    private var dailyCount = 0
    private var dailyWindowStart = Date()

    init(minuteCapacity: Int = 90, dailyCapacity: Int = 9500) {
        self.minuteCapacity = minuteCapacity
        self.dailyCapacity = dailyCapacity
    }

    /// Blocks until a request is safe to send, then reserves a slot.
    func acquire() async {
        resetWindowsIfElapsed()
        while minuteCount >= minuteCapacity || dailyCount >= dailyCapacity {
            let wait = minuteCount >= minuteCapacity ? secondsUntilMinuteReset() : secondsUntilDailyReset()
            try? await Task.sleep(nanoseconds: UInt64(max(wait, 0.5) * 1_000_000_000))
            resetWindowsIfElapsed()
        }
        minuteCount += 1
        dailyCount += 1
    }

    /// Tightens the local estimate from a response's rate-limit headers. Only
    /// moves the local count *up* to match a lower remaining-count from the
    /// server — never down, since that would let us exceed the real limit based
    /// on a stale/looser local guess.
    func recordHeaders(remaining: Int?, resetSeconds: Int?) {
        guard let remaining else { return }
        let serverImpliedCount = minuteCapacity - remaining
        if serverImpliedCount > minuteCount {
            minuteCount = serverImpliedCount
        }
        if let resetSeconds, resetSeconds > 0 {
            // Re-anchor the window so our local reset time matches the server's,
            // rather than drifting from whenever we happened to start counting.
            minuteWindowStart = Date().addingTimeInterval(-Double(60 - resetSeconds))
        }
    }

    /// Called on an actual 429 — trusts the server's reset hint over any local
    /// estimate, since local bookkeeping already proved wrong.
    func handleRateLimitExceeded(resetSeconds: Int?) async {
        let wait = TimeInterval(resetSeconds ?? 60)
        minuteCount = minuteCapacity // don't let acquire() hand out more slots until the wait clears
        try? await Task.sleep(nanoseconds: UInt64(max(wait, 0.5) * 1_000_000_000))
        resetWindowsIfElapsed(force: true)
    }

    private func resetWindowsIfElapsed(force: Bool = false) {
        let now = Date()
        if force || now.timeIntervalSince(minuteWindowStart) >= 60 {
            minuteWindowStart = now
            minuteCount = 0
        }
        if force || now.timeIntervalSince(dailyWindowStart) >= 86400 {
            dailyWindowStart = now
            dailyCount = 0
        }
    }

    private func secondsUntilMinuteReset() -> TimeInterval {
        max(0, 60 - Date().timeIntervalSince(minuteWindowStart))
    }

    private func secondsUntilDailyReset() -> TimeInterval {
        max(0, 86400 - Date().timeIntervalSince(dailyWindowStart))
    }

    /// Test-only peek at internal state — `internal`, not `private`, purely so
    /// `@testable import` can see it. Never called from production code.
    func currentMinuteCountForTesting() -> Int { minuteCount }
}
