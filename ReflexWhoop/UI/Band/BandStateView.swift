import SwiftUI

/// Band when it isn't streaming: not recording, looking for the band, or
/// Bluetooth in the way, each with the one thing that fixes it.
struct BandStateView: View {
    let presentation: BandPresentation
    let startRecording: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
                .foregroundStyle(.secondary)
        } actions: {
            switch presentation {
            case .idle:
                Button("Start recording", action: startRecording)
                    .buttonStyle(.primary)
            case .bluetoothDenied:
                Button("Open Settings", action: openSettings)
                    .buttonStyle(.primary)
            case .live, .searching, .bluetoothOff, .unsupported:
                EmptyView()
            }
        }
    }

    private var title: String {
        switch presentation {
        case .idle: "Record from your band"
        case .live, .searching: "Looking for your band"
        case .bluetoothOff: "Bluetooth is off"
        case .bluetoothDenied: "Bluetooth is turned off for ReflexWhoop"
        case .unsupported: "This iPhone can't use Bluetooth"
        }
    }

    private var message: String {
        switch presentation {
        case .idle: "Connects straight to the band over Bluetooth and keeps recording in the background. No account or internet needed."
        case .live, .searching: "Keep it within a few metres. Recording carries on by itself when it reconnects. Heart rate from while the band is away isn't recorded."
        case .bluetoothOff: "Turn it on in Control Center to record from your band."
        case .bluetoothDenied: "The app needs Bluetooth to hear your band. It only ever reads from it."
        case .unsupported: "Recording from the band needs Bluetooth."
        }
    }

    private var systemImage: String {
        switch presentation {
        case .idle: "applewatch"
        case .live, .searching: "antenna.radiowaves.left.and.right"
        case .bluetoothOff, .bluetoothDenied, .unsupported: "exclamationmark.triangle"
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}
