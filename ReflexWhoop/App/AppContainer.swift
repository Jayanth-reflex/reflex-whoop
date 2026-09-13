import Foundation
import Observation

/// Composition root. Owns every long-lived service and hands them to views via
/// the SwiftUI environment. Phase 1 wired up storage; Phase 2 adds Auth/Api/Sync.
@Observable
final class AppContainer {
    let database: Database
    let auth: WhoopAuth

    /// Bumped whenever sign-in state changes, so views observing this property
    /// (not `auth` itself, which isn't `@Observable`-visible across an actor
    /// boundary) know to refresh.
    private(set) var isSignedIn = false

    init() throws {
        database = try Database(path: try Database.defaultPath())
        auth = WhoopAuth()
    }

    @MainActor
    func refreshSignInState() async {
        isSignedIn = (try? await auth.isSignedIn()) ?? false
    }

    @MainActor
    func signIn() async throws {
        try await auth.login()
        await refreshSignInState()
    }

    @MainActor
    func signOut() async {
        // Best-effort server-side revoke; local sign-out must succeed regardless
        // of network state — a personal app's "sign out" button can't depend on
        // connectivity.
        if let engine = await syncEngine() {
            try? await engine.client.revokeAccess()
        }
        try? await auth.signOut()
        await refreshSignInState()
    }

    /// `nil` when there's nothing to sync with yet (no client credentials saved).
    /// Signed-out-but-credentialed still returns an engine — the first sync
    /// attempt is what surfaces `.notAuthenticated` to the caller.
    func syncEngine() async -> ApiSyncEngine? {
        guard (try? TokenStore.loadClientCredentials()) != nil else { return nil }
        let client = WhoopClient(auth: auth)
        return ApiSyncEngine(client: client, dbPool: database.dbPool)
    }

    private static let lastForegroundSyncKey = "lastForegroundSyncAttempt"
    private static let foregroundSyncDebounce: TimeInterval = 15 * 60

    /// The third sync trigger from the design doc's "app foreground (debounced
    /// 15 min)" — call from the root view whenever the app becomes active.
    /// Debounce state lives in `UserDefaults` (not memory) so it survives the
    /// app being killed and relaunched, which on a free Apple ID's 7-day-expiry
    /// build happens often.
    ///
    /// Checks `auth.isSignedIn()` directly rather than the `isSignedIn`
    /// published property: this can run from `RootView`'s own `.task` on the
    /// very first launch, before `refreshSignInState()` (a separate `.task`,
    /// unordered relative to this one) has had a chance to set that property —
    /// reading the cached flag here would silently skip the first sync on a
    /// fresh launch until the next foreground event.
    func syncIfDueOnForeground() async {
        guard (try? await auth.isSignedIn()) == true else { return }
        let lastAttempt = UserDefaults.standard.object(forKey: Self.lastForegroundSyncKey) as? Date
        if let lastAttempt, Date().timeIntervalSince(lastAttempt) < Self.foregroundSyncDebounce { return }

        UserDefaults.standard.set(Date(), forKey: Self.lastForegroundSyncKey)
        guard let engine = await syncEngine() else { return }
        _ = try? await engine.syncNow(trigger: "foreground")
    }

    struct SourceSnapshot {
        var whoop: SourceState
        var band: SourceState
        var archive: ArchiveSummary
    }

    /// One read of "what can still collect, and what do we already hold" —
    /// docs/ADR-001-data-sovereignty.md's archive mode. Deliberately returns
    /// both together: the whole point is that a dead source is reported
    /// alongside an intact archive, never as a bare failure.
    func sourceSnapshot() async -> SourceSnapshot {
        let isSignedIn = (try? await auth.isSignedIn()) ?? false
        let hasCredentials = (try? TokenStore.loadClientCredentials()) != nil
        let snapshot = try? await database.dbPool.read { db in
            SourceSnapshot(
                whoop: try SourceStatus.whoop(db, isSignedIn: isSignedIn, hasCredentials: hasCredentials),
                band: try SourceStatus.band(db),
                archive: try SourceStatus.archive(db)
            )
        }
        return snapshot ?? SourceSnapshot(
            whoop: hasCredentials ? .unauthorized : .notConfigured,
            band: .notConfigured,
            archive: ArchiveSummary(firstDay: nil, lastDay: nil, dayCount: 0, bleSessionCount: 0, bleSampleCount: 0)
        )
    }

    /// Normalizes any BLE session that still has undecoded inbox rows. Called on
    /// launch, so sessions recorded before the normalizer existed — or by a
    /// build that crashed before finishing — heal themselves without the user
    /// knowing a button exists. Idempotent and a no-op when nothing is pending.
    ///
    /// Deliberately not gated on WHOOP auth: the band is an independent source,
    /// and making its pipeline wait on an unrelated account's sign-in state is
    /// exactly the coupling docs/ADR-001-data-sovereignty.md argues against.
    func normalizeBleIfNeeded() async {
        let dbPool = database.dbPool
        _ = try? await Task.detached(priority: .utility) {
            try BleNormalizer.processPending(dbPool)
        }.value
    }

    /// Re-derives every BLE session's time series from the inbox bytes. Exposed
    /// as a deliberate user action (Data tab) because it rewrites every chunk.
    func replayBleNormalization() async throws -> BleNormalizer.Stats {
        let dbPool = database.dbPool
        return try await Task.detached { try BleNormalizer.replay(dbPool) }.value
    }

    /// Phase 4. Deliberately not a stored property: constructing a
    /// `SpikeRecorder` doesn't touch Bluetooth by itself (that only happens on
    /// `startSession`), but keeping it request-scoped means `LiveView` controls
    /// exactly when a `CBCentralManager` gets created, which is what triggers
    /// the OS Bluetooth-permission prompt.
    @MainActor
    func makeSpikeRecorder() -> SpikeRecorder {
        SpikeRecorder(dbPool: database.dbPool)
    }
}
