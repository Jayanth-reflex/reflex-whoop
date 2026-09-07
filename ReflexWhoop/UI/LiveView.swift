import SwiftUI

/// Phase 4: connect to the band over BLE and run the Gen 5 discovery spike
/// (docs/design.md, "Gen 5 discovery spike") — connect, send the safe
/// read-only command sequence, and log every raw frame for offline analysis.
/// This screen is intentionally low-level (raw counters, not decoded metrics)
/// because nothing is decoded yet: that's the point of the spike.
struct LiveView: View {
    @Environment(AppContainer.self) private var container
    @State private var recorder: SpikeRecorder?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(
                        "Read-only session. This app never requests historical data from the band and cannot modify it — see the BLE safety rails in Settings.",
                        systemImage: "checkmark.shield"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                if let recorder {
                    statusSection(recorder)
                    if let bpm = recorder.lastHeartRateBpm {
                        Section("Heart rate") {
                            LabeledContent("Latest reading") {
                                Text("\(bpm) bpm").font(.title2.monospacedDigit())
                            }
                            Text("Unscaled byte from the 0x28 realtime record — see docs/PROTOCOL-GEN5.md. Not yet cross-checked against the official app's own reading.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    countersSection(recorder)
                    if let inner = recorder.lastHelloInner {
                        Section("HELLO response (envelope confirmed)") {
                            Text(inner.map { String(format: "%02X", $0) }.joined(separator: " "))
                                .font(.system(.footnote, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }

                Section {
                    if recorder == nil {
                        Button("Start discovery spike") { start() }
                    } else {
                        Button("Stop session", role: .destructive) { stop() }
                    }
                }
            }
            .navigationTitle("Live")
        }
    }

    private func statusSection(_ recorder: SpikeRecorder) -> some View {
        Section("Connection") {
            LabeledContent("State", value: describe(recorder.connectionState))
        }
    }

    private func countersSection(_ recorder: SpikeRecorder) -> some View {
        Section("This session") {
            LabeledContent("Raw frames logged", value: "\(recorder.frameCount)")
            LabeledContent("Bytes logged", value: "\(recorder.byteCount)")
            LabeledContent("Reassembled candidates", value: "\(recorder.reassembledFrameCount)")
            LabeledContent("CRC-valid frames", value: "\(recorder.validCrcFrameCount)")
        }
    }

    private func describe(_ state: BandConnection.ConnectionState) -> String {
        switch state {
        case .idle: return "Idle"
        case .unavailable(let reason): return reason
        case .scanning: return "Scanning…"
        case .connecting: return "Connecting…"
        case .discoveringServices: return "Discovering services…"
        case .subscribing: return "Subscribing…"
        case .ready: return "Connected"
        case .disconnected(let reason): return "Disconnected (\(reason))"
        }
    }

    private func start() {
        let newRecorder = container.makeSpikeRecorder()
        recorder = newRecorder
        try? newRecorder.startSession()
        Task {
            // Poll for "ready" rather than wiring a callback — this view only
            // needs to fire the safe command sequence once, and connection
            // setup is a handful of round trips, not a hot loop.
            for _ in 0..<200 {
                if newRecorder.connectionState == .ready {
                    newRecorder.beginSafeCommandSequence()
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func stop() {
        recorder?.stopSession()
        recorder = nil
    }
}

#Preview {
    LiveView()
}
