import Foundation

/// Runs one WHOOP sync at a time, app-wide. A sync asked for while another is running
/// joins it and gets its result, instead of starting a second.
///
/// Opening the app started a foreground sync from two places at once, and a pull or a
/// manual "Sync now" could land in the same second; each built its own engine, so
/// nothing knew another was running. On 26 September three overlapping syncs each tried
/// to refresh the WHOOP token, none got one back, and sync stayed broken for ten hours
/// until a re-login. `WhoopAuth.refreshOnce()` now serializes the refresh itself; this
/// stops the duplicate work — and the duplicate API requests — that set it up.
///
/// An actor alone doesn't guarantee this: it yields at every `await`. What does is that
/// the in-flight task is stored and awaited with no `await` in between, the same shape
/// as `refreshOnce()`.
actor SyncRunner {
    private var inFlight: Task<ApiSyncEngine.Summary, Error>?

    func run(_ sync: @escaping @Sendable () async throws -> ApiSyncEngine.Summary) async throws -> ApiSyncEngine.Summary {
        if let inFlight {
            return try await inFlight.value
        }
        let task = Task { try await sync() }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }
}
