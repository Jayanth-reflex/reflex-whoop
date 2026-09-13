import SwiftUI

/// Saves the client ID and secret of the person's own WHOOP developer app to
/// Keychain, then opens WHOOP's sign-in.
struct WhoopCredentialsForm: View {
    let onConnected: () -> Void

    @Environment(AppContainer.self) private var container

    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var isConnecting = false
    @State private var errorText: String?

    private static let developerSite = URL(string: "https://developer.whoop.com")

    private var hasBothFields: Bool {
        !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !clientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        List {
            Group {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Connect your WHOOP account")
                            .font(.display(.title))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("ReflexWhoop signs in through your own WHOOP developer app. Paste its client ID and secret.")
                    }
                }
                .listRowBackground(Color.clear)

                Section {
                    TextField("Client ID", text: $clientID)
                    SecureField("Secret", text: $clientSecret)
                } footer: {
                    Label("Kept in this iPhone's Keychain and only used to sign in to WHOOP.", systemImage: "lock")
                        .foregroundStyle(.secondary)
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(nil)
                .submitLabel(.done)

                if let developerSite = Self.developerSite {
                    Section {
                        Link(destination: developerSite) {
                            LabeledContent("Where do I find these?") {
                                Image(systemName: "arrow.up.forward")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .accessibilityHint("Opens WHOOP's developer site")
                    }
                }

                Section {
                    Button(action: startConnect) {
                        if isConnecting {
                            ProgressView()
                                .tint(Color.onChampagne)
                        } else {
                            Text("Connect")
                        }
                    }
                    .buttonStyle(.primary)
                    .disabled(!hasBothFields)
                    if let errorText {
                        InlineMessage(text: errorText)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            .listRowBackground(Color.surface)
        }
    }

    private func startConnect() {
        guard !isConnecting else { return }
        Task { await connect() }
    }

    private func connect() async {
        isConnecting = true
        defer { isConnecting = false }
        do {
            try TokenStore.saveClientCredentials(
                clientID: clientID.trimmingCharacters(in: .whitespacesAndNewlines),
                clientSecret: clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            try await container.signIn()
            errorText = nil
            onConnected()
        } catch is CancellationError {
            // Closing WHOOP's sign-in sheet keeps the credentials; the account
            // screen now offers Sign in.
            onConnected()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
