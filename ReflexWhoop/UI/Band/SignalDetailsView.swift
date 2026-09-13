import SwiftUI

/// What the band has sent this session, for decoding work. Protocol terms are
/// allowed here and nowhere else in the app.
struct SignalDetailsView: View {
    let recorder: SpikeRecorder

    var body: some View {
        List {
            Group {
                Section {
                    Text("For decoding work. Nothing on this screen changes how the band behaves.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Color.clear)

                Section {
                    LabeledContent("Packets received", value: recorder.frameCount.formatted())
                    LabeledContent("Read as heart rate", value: recorder.heartRateReadingCount.formatted())
                    LabeledContent("Not readable yet", value: max(recorder.validCrcFrameCount - recorder.heartRateReadingCount, 0).formatted())
                    LabeledContent("Damaged", value: max(recorder.reassembledFrameCount - recorder.validCrcFrameCount, 0).formatted())
                    if let difference = recorder.hrCrossCheckDiffBpm {
                        LabeledContent("R10 heart-rate cross-check", value: "\(difference.formatted(.number.sign(strategy: .always()))) bpm")
                    }
                } header: {
                    SectionHeader(title: "This session")
                } footer: {
                    SectionFooter(text: "Heart rate is one of several signals the band sends, so a low share of readable packets is expected. It isn't a quality problem.")
                }

                if !recorder.packetTypeCounts.sortedByCount.isEmpty {
                    Section {
                        ForEach(recorder.packetTypeCounts.sortedByCount, id: \.packetType) { entry in
                            LabeledContent {
                                Text(entry.count.formatted())
                                    .monospacedDigit()
                            } label: {
                                Text(PacketTypeCounts.label(for: entry.packetType))
                                    .monospaced()
                            }
                        }
                    } header: {
                        SectionHeader(title: "Packet types")
                    }
                }

                if !recorder.deviceMetadataStrings.isEmpty {
                    Section {
                        ForEach(recorder.deviceMetadataStrings, id: \.self) { string in
                            Text(string)
                                .monospaced()
                                .textSelection(.enabled)
                        }
                    } header: {
                        SectionHeader(title: "Band reports")
                    }
                }

                if !recorder.commandResults.isEmpty {
                    Section {
                        ForEach(recorder.commandResults, id: \.opcode) { result in
                            Label {
                                Text(result.opcode)
                                    .monospaced()
                            } icon: {
                                Image(systemName: result.succeeded ? "checkmark" : "xmark")
                                    .foregroundStyle(result.succeeded ? Color.jade : Color.garnet)
                            }
                            .accessibilityValue(result.succeeded ? "Sent" : "Failed")
                        }
                    } header: {
                        SectionHeader(title: "Startup commands")
                    }
                }

                Section {
                    Label {
                        SubtitledRow(title: "Read-only connection", subtitle: "Can't change settings, clock or alarms, and never asks the band for its stored history.")
                    } icon: {
                        Image(systemName: "lock")
                    }
                } header: {
                    SectionHeader(title: "Safety")
                }
            }
            .listRowBackground(Color.surface)
        }
        .navigationTitle("Signal details")
        .navigationBarTitleDisplayMode(.inline)
    }
}
