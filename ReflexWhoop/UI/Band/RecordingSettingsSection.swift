import SwiftUI

/// The Keep recording switch, with what the current session has captured.
struct RecordingSettingsSection: View {
    @Binding var keepRecording: Bool
    let recorder: SpikeRecorder?

    var body: some View {
        Section {
            Toggle("Keep recording", isOn: $keepRecording)
            if let recorder, let startedAt = recorder.sessionStartedAt, recorder.heartRateReadingCount > 0 {
                LabeledContent("This session") {
                    Text("\(startedAt, style: .relative) · \(recorder.heartRateReadingCount.formatted()) readings")
                        .monospacedDigit()
                }
                if recorder.connectionState != .ready, let lastReading = recorder.recentHeartRate.readings.last {
                    LabeledContent("Last heard from") {
                        Text(lastReading.time, format: .dateTime.hour().minute())
                    }
                }
            }
        } header: {
            SectionHeader(title: "Recording")
        } footer: {
            SectionFooter(text: "Stays connected in the background and reconnects when the band is back in range. No account or internet needed. Uses more battery on both.")
        }
    }
}
