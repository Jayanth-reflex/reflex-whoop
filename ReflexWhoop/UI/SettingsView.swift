import SwiftUI

/// Phase 2 adds credentials + re-auth here. Phase 4 adds capture defaults and the
/// storage soft budget. Danger-zone wipe and export land with Phase 5.
struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("WHOOP Account") {
                    Text("Not connected").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
