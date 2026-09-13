import SwiftUI

/// Every past recording, newest first.
struct RecordingsListView: View {
    let recordings: [RecordingSummary]

    var body: some View {
        List {
            Section {
                ForEach(recordings) { recording in
                    NavigationLink(value: recording) {
                        RecordingRow(recording: recording)
                    }
                }
            } footer: {
                SectionFooter(text: "Recordings are never deleted by the app.")
            }
            .listRowBackground(Color.surface)
        }
        .navigationTitle("All recordings")
        .navigationBarTitleDisplayMode(.inline)
    }
}
