import SwiftUI

/// The WHOOP account: its state, the one action that moves it forward, and
/// what it brings in. Not set up shows the credentials form instead.
struct WhoopAccountView: View {
    @Environment(AppContainer.self) private var container

    @State private var sources: AppContainer.SourceSnapshot?
    @State private var history: WhoopHistory?
    @State private var isWorking = false
    @State private var actionError: String?
    @State private var isConfirmingForget = false

    var body: some View {
        Group {
            switch sources?.whoop {
            case nil:
                ProgressView()
            case .notConfigured:
                WhoopCredentialsForm(onConnected: reload)
            case let whoop?:
                List {
                    Group {
                        Section {
                            WhoopStatusHeader(state: whoop, archive: sources?.archive)
                        }
                        .listRowBackground(Color.clear)

                        WhoopActionSection(state: whoop, isWorking: isWorking, error: actionError, syncNow: startSync, signIn: startSignIn)

                        if case .inactive = whoop {
                            WhoopEndedSections(dayCount: sources?.archive.dayCount ?? 0)
                        } else if let history {
                            WhoopHistorySection(history: history)
                        }

                        Section {
                            Label {
                                SubtitledRow(title: "Your developer app", subtitle: "Client ID and secret in Keychain")
                            } icon: {
                                Image(systemName: "key")
                            }
                        } header: {
                            SectionHeader(title: "Signed in with")
                        }

                        Section {
                            if case .unauthorized = whoop {
                                Button("Forget saved credentials", role: .destructive, action: askToForget)
                                    .frame(maxWidth: .infinity)
                                    .confirmationDialog("Forget your WHOOP credentials?", isPresented: $isConfirmingForget, titleVisibility: .visible) {
                                        Button("Forget", role: .destructive, action: forgetCredentials)
                                    } message: {
                                        Text("Removes the client ID and secret from Keychain. Everything already on this iPhone stays.")
                                    }
                            } else {
                                Button("Sign out", role: .destructive, action: startSignOut)
                                    .frame(maxWidth: .infinity)
                                    .disabled(isWorking)
                            }
                        } footer: {
                            SectionFooter(text: "Signing out keeps everything already on this iPhone.")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .listRowBackground(Color.surface)
                }
            }
        }
        .navigationTitle("WHOOP account")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        sources = await container.sourceSnapshot()
        history = try? await container.database.dbPool.read(WhoopHistory.load)
    }

    private func reload() {
        Task { await load() }
    }

    private func startSync() {
        Task { await run { try await syncNow() } }
    }

    private func startSignIn() {
        Task { await run { try await container.signIn() } }
    }

    private func startSignOut() {
        Task { await run { await container.signOut() } }
    }

    private func askToForget() {
        isConfirmingForget = true
    }

    private func forgetCredentials() {
        do {
            try TokenStore.clearAll()
            actionError = nil
        } catch {
            actionError = "Couldn't remove the credentials: \(error.localizedDescription)"
        }
        reload()
    }

    private func syncNow() async throws {
        guard let engine = await container.syncEngine() else { return }
        try await engine.syncNow(trigger: "manual")
    }

    /// Runs an account action with the working state and in-place error text,
    /// then rereads the account. Closing WHOOP's sign-in sheet isn't an error.
    private func run(_ action: () async throws -> Void) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await action()
            actionError = nil
        } catch is CancellationError {
            actionError = nil
        } catch {
            actionError = error.localizedDescription
        }
        await load()
    }
}
