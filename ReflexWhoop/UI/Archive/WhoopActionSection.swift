import SwiftUI

/// The one action that moves the account forward from its state, with any
/// error it hit shown beneath it.
struct WhoopActionSection: View {
    let state: SourceState
    let isWorking: Bool
    let error: String?
    let syncNow: () -> Void
    let signIn: () -> Void

    var body: some View {
        Section {
            HStack {
                switch state {
                case .unauthorized:
                    Button("Sign in", systemImage: "person.crop.circle", action: signIn)
                case .inactive:
                    Button("Check again", systemImage: "arrow.clockwise", action: syncNow)
                case .active, .unreachable, .notConfigured:
                    Button("Sync now", systemImage: "arrow.clockwise", action: syncNow)
                }
                Spacer()
                if isWorking {
                    ProgressView()
                }
            }
            .disabled(isWorking)
            if let error {
                InlineMessage(text: error)
            }
        } footer: {
            SectionFooter(text: footer)
        }
    }

    private var footer: String {
        switch state {
        case .inactive: "If you rejoin, syncing picks up from where it stopped."
        case .unauthorized: "Opens WHOOP's sign-in page."
        case .active, .unreachable, .notConfigured: "Also syncs by itself each time you open the app."
        }
    }
}
