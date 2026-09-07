import SwiftUI

struct SettingsView: View {
    @Environment(AppContainer.self) private var container

    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var hasSavedCredentials = false
    @State private var isWorking = false
    @State private var statusMessage: String?
    @State private var lastSyncSummary: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("WHOOP Account") {
                    if container.isSignedIn {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Button("Sync now") { Task { await syncNow() } }
                            .disabled(isWorking)
                        Button("Sign out", role: .destructive) { Task { await signOut() } }
                            .disabled(isWorking)
                    } else if hasSavedCredentials {
                        Label("Credentials saved — not connected", systemImage: "circle")
                            .foregroundStyle(.secondary)
                        Button("Connect to WHOOP") { Task { await signIn() } }
                            .disabled(isWorking)
                    } else {
                        Text("Enter your WHOOP developer app credentials to connect.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        SecureField("Client ID", text: $clientID)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("Client Secret", text: $clientSecret)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Save credentials") { saveCredentials() }
                            .disabled(clientID.isEmpty || clientSecret.isEmpty)
                    }

                    if let statusMessage {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    if let lastSyncSummary {
                        Text(lastSyncSummary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
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
            .navigationTitle("Settings")
            .task { checkSavedCredentials() }
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
