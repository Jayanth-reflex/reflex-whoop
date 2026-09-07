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
