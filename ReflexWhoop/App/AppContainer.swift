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
}
