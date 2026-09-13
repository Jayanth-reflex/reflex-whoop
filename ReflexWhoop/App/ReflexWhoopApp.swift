import SwiftUI

@main
struct ReflexWhoopApp: App {
    @State private var container: AppContainer

    init() {
        // Before any navigation bar exists, so every bar picks up the serif titles.
        MainActor.assumeIsolated { NavigationBarStyle.apply() }

        // AppContainer opens/migrates the database on construction. If this throws,
        // there is nothing sensible to show the user — better to crash loudly during
        // development than to silently run against a half-initialized store.
        do {
            let container = try AppContainer()
            _container = State(initialValue: container)
            // Must register before the app finishes launching, or a background
            // launch specifically to run this task silently no-ops.
            BackgroundSync.register(container: container)
            // Same reason, for Bluetooth: a background relaunch to deliver a
            // BLE event needs the central manager re-created during launch, or
            // Core Bluetooth's restoration callback never fires.
            MainActor.assumeIsolated { container.startContinuousCollectionIfEnabled() }
        } catch {
            fatalError("Failed to initialize app container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(container)
                .preferredColorScheme(.dark)
                .foregroundStyle(Color.ivory)
                .labeledContentStyle(.secondaryValue)
                .task { await container.refreshSignInState() }
        }
    }
}
