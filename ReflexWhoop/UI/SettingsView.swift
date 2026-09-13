import SwiftUI

struct SettingsView: View {
    @Environment(AppContainer.self) private var container

    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var hasSavedCredentials = false
    @State private var isWorking = false
    @State private var statusMessage: String?
    @State private var lastSyncSummary: String?

    @State private var sources: AppContainer.SourceSnapshot?
    @State private var continuousCollection = CollectionSettings.continuousCollectionEnabled

    private func sourceRow(_ name: String, state: SourceState) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(name).foregroundStyle(Theme.text)
                Spacer()
                HStack(spacing: 6) {
                    Circle()
                        .fill(state.canCollect ? Theme.vital : Theme.muted)
                        .frame(width: 6, height: 6)
                    Text(state.label).foregroundStyle(Theme.muted)
                }
            }
            if let detail = state.detail {
                Text(detail).font(.caption).foregroundStyle(Theme.muted)
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let sources {
                    Section("Where data comes from") {
                        sourceRow("WHOOP account", state: sources.whoop)
                        sourceRow("Band", state: sources.band)
                    }
                }

                Section {
                    Toggle("Keep recording", isOn: Binding(
                        get: { continuousCollection },
                        set: { newValue in
                            continuousCollection = newValue
                            container.setContinuousCollection(newValue)
                        }
                    ))
                    .tint(Theme.vital)
                } header: {
                    Text("Band")
                } footer: {
                    Text("Stays connected and keeps saving heart rate in the background, reconnecting on its own when the band comes back in range. Needs no account and no internet. Uses more battery on the phone and the band.")
                }

                Section("WHOOP account") {
                    if container.isSignedIn {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Theme.vital)
                        Button("Sync now") { Task { await syncNow() } }
                            .disabled(isWorking)
                        Button("Sign out", role: .destructive) { Task { await signOut() } }
                            .disabled(isWorking)
                    } else if hasSavedCredentials {
                        Text("Saved, but not connected")
                            .foregroundStyle(Theme.muted)
                        Button("Connect") { Task { await signIn() } }
                            .disabled(isWorking)
                    } else {
                        Text("Paste the client ID and secret from your WHOOP developer app.")
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                        SecureField("Client ID", text: $clientID)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("Client Secret", text: $clientSecret)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Save") { saveCredentials() }
                            .disabled(clientID.isEmpty || clientSecret.isEmpty)
                    }

                    if let statusMessage {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(Theme.alert)
                    }
                    if let lastSyncSummary {
                        Text(lastSyncSummary)
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                    }
                }

                if hasSavedCredentials {
                    Section {
                        Button("Forget saved credentials", role: .destructive) {
                            try? TokenStore.clearAll()
                            hasSavedCredentials = false
                            clientID = ""
                            clientSecret = ""
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.ink)
            .navigationTitle("Settings")
            .toolbarBackground(Theme.ink, for: .navigationBar)
            .tint(Theme.vital)
            .task {
                checkSavedCredentials()
                sources = await container.sourceSnapshot()
            }
        }
    }

    private func checkSavedCredentials() {
        hasSavedCredentials = (try? TokenStore.loadClientCredentials()) != nil
    }

    private func saveCredentials() {
        do {
            try TokenStore.saveClientCredentials(clientID: clientID, clientSecret: clientSecret)
            hasSavedCredentials = true
            statusMessage = nil
        } catch {
            statusMessage = "Couldn't save credentials: \(error.localizedDescription)"
        }
    }

    private func signIn() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await container.signIn()
            statusMessage = nil
            await syncNow()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func signOut() async {
        isWorking = true
        defer { isWorking = false }
        await container.signOut()
        lastSyncSummary = nil
    }

    private func syncNow() async {
        isWorking = true
        defer { isWorking = false }
        guard let engine = await container.syncEngine() else {
            statusMessage = "No credentials saved."
            return
        }
        do {
            let summary = try await engine.syncNow(trigger: "manual")
            lastSyncSummary = "Synced: \(summary.requestsMade) requests, \(summary.recordsUpserted) records updated."
            statusMessage = nil
        } catch {
            statusMessage = "Sync failed: \(error.localizedDescription)"
        }
    }
}
