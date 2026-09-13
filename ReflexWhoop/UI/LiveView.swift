import SwiftUI

/// Recording live from the band.
///
/// Two audiences, one screen, in priority order: what a person wants while
/// wearing the band (is it connected, what's my heart rate, is it recording),
/// and — folded away underneath — the protocol diagnostics that are only
/// meaningful while the Gen 5 decoding work is still in progress.
struct LiveView: View {
    @Environment(AppContainer.self) private var container
    @State private var ownRecorder: SpikeRecorder?
    @State private var showDiagnostics = false

    /// Continuous collection owns a recorder for the app's lifetime; this
    /// screen observes it rather than starting a competing session, since two
    /// centrals fighting over one peripheral does not work.
    private var recorder: SpikeRecorder? { container.continuousRecorder ?? ownRecorder }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ink.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.gutter) {
                        if let recorder {
                            heartRate(recorder)
                            status(recorder)
                            diagnostics(recorder)
                        } else {
                            idle
                        }
                        controls
                    }
                    .padding(Theme.gutter)
                }
            }
            .navigationTitle("Live")
            .toolbarBackground(Theme.ink, for: .navigationBar)
        }
    }

    // MARK: - Idle

    private var idle: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.vital)
            Text("Record from the band")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.text)
            Text("Connects straight to the band over Bluetooth and saves heart rate as it comes in. Works with no internet and no WHOOP account.")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Label("Only reads from the band. It can't change anything on it.", systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Heart rate hero

    private func heartRate(_ recorder: SpikeRecorder) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow("Heart rate", tint: recorder.lastHeartRateBpm == nil ? Theme.muted : Theme.vital)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(recorder.lastHeartRateBpm.map { "\($0)" } ?? "—")
                        .font(Theme.readout(56))
                        .foregroundStyle(recorder.lastHeartRateBpm == nil ? Theme.muted : Theme.text)
                    Text("bpm")
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.muted)
                }
                Text(recorder.lastHeartRateBpm == nil
                     ? "Waiting for the first reading."
                     : "Live from the band. Not yet checked against WHOOP's own number.")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    // MARK: - Status

    private func status(_ recorder: SpikeRecorder) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Eyebrow("Connection")
                    Spacer()
                    HStack(spacing: 6) {
                        Circle()
                            .fill(recorder.connectionState == .ready ? Theme.vital : Theme.caution)
                            .frame(width: 6, height: 6)
                        Text(describe(recorder.connectionState))
                            .font(.subheadline)
                            .foregroundStyle(Theme.text)
                    }
                }
                Divider().overlay(Theme.stroke)
                HStack {
                    Text("Recorded this session")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: Int64(recorder.byteCount), countStyle: .file))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Theme.text)
                }
                if container.continuousRecorder != nil {
                    Label("Keeps recording in the background and reconnects on its own.", systemImage: "infinity")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
            }
        }
    }

    // MARK: - Diagnostics

    /// Everything below is about the reverse-engineering effort rather than
    /// about the wearer, so it stays collapsed. It is kept because this app's
    /// user is also the person decoding the protocol — but it is not what the
    /// screen is *for*.
    private func diagnostics(_ recorder: SpikeRecorder) -> some View {
        Card {
            DisclosureGroup(isExpanded: $showDiagnostics) {
                VStack(alignment: .leading, spacing: 16) {
                    channelActivity(recorder)
                    if !recorder.deviceMetadataStrings.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Eyebrow("Band reports")
                            ForEach(recorder.deviceMetadataStrings, id: \.self) {
                                Text($0)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(Theme.text)
                            }
                        }
                    }
                    frameStats(recorder)
                    if !recorder.commandResults.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Eyebrow("Startup commands")
                            ForEach(recorder.commandResults, id: \.opcode) { result in
                                HStack {
                                    Text(result.opcode)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(Theme.muted)
                                    Spacer()
                                    Image(systemName: result.succeeded ? "checkmark" : "xmark")
                                        .font(.caption2.bold())
                                        .foregroundStyle(result.succeeded ? Theme.vital : Theme.alert)
                                }
                            }
                        }
                    }
                }
                .padding(.top, 12)
            } label: {
                Eyebrow("Signal details")
            }
            .tint(Theme.muted)
        }
    }

    private func channelActivity(_ recorder: SpikeRecorder) -> some View {
        let entries = recorder.packetTypeCounts.sortedByCount
        return VStack(alignment: .leading, spacing: 6) {
            Eyebrow("Channels seen")
            if entries.isEmpty {
                Text("Nothing yet.").font(.caption).foregroundStyle(Theme.muted)
            } else {
                ForEach(entries, id: \.packetType) { entry in
                    HStack {
                        Text(PacketTypeCounts.label(for: entry.packetType))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Theme.muted)
                        Spacer()
                        Text("\(entry.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.text)
                    }
                }
                Text("Which kinds of data the band is sending. Only heart rate is decoded so far; the rest is saved raw for later.")
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    private func frameStats(_ recorder: SpikeRecorder) -> some View {
        HStack(spacing: 24) {
            Readout(label: "Received", value: "\(recorder.frameCount)", size: 18)
            Readout(label: "Usable", value: "\(recorder.validCrcFrameCount)", size: 18)
            if let diff = recorder.hrCrossCheckDiffBpm {
                Readout(label: "HR delta", value: "\(diff > 0 ? "+" : "")\(diff)", unit: "bpm", size: 18)
            }
        }
    }

    // MARK: - Controls

    @ViewBuilder
    private var controls: some View {
        if container.continuousRecorder != nil {
            Text("Continuous recording is on. Turn it off in Settings to control sessions here.")
                .font(.caption)
                .foregroundStyle(Theme.muted)
        } else if ownRecorder == nil {
            Button {
                let recorder = container.makeSpikeRecorder()
                ownRecorder = recorder
                try? recorder.startSession()
            } label: {
                Text("Start recording").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.vital)
            .foregroundStyle(Theme.ink)
            .controlSize(.large)
        } else {
            Button(role: .destructive) {
                ownRecorder?.stopSession()
                ownRecorder = nil
            } label: {
                Text("Stop recording").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Theme.alert)
            .controlSize(.large)
        }
    }

    private func describe(_ state: BandConnection.ConnectionState) -> String {
        switch state {
        case .idle: "Not connected"
        case .unavailable(let reason): reason
        case .scanning: "Looking for your band"
        case .connecting: "Connecting"
        case .discoveringServices, .subscribing: "Setting up"
        case .ready: "Connected"
        case .disconnected: "Reconnecting"
        }
    }
}
