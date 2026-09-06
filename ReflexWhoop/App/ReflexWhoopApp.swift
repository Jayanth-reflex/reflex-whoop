import SwiftUI

@main
struct ReflexWhoopApp: App {
    @State private var container: AppContainer

    init() {
        // AppContainer opens/migrates the database on construction. If this throws,
        // there is nothing sensible to show the user — better to crash loudly during
        // development than to silently run against a half-initialized store.
        do {
            _container = State(initialValue: try AppContainer())
        } catch {
            fatalError("Failed to initialize app container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(container)
                .preferredColorScheme(.dark)
        }
    }
}
