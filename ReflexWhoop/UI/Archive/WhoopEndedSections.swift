import SwiftUI

/// After a membership ends: what still works, and what's paused.
struct WhoopEndedSections: View {
    let dayCount: Int

    var body: some View {
        Section {
            ForEach(["Heart rate from your band", "All \(dayCount.formatted()) days of history", "Trends and patterns on that history", "Exporting a copy"], id: \.self) { item in
                Label {
                    Text(item)
                } icon: {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.jade)
                }
            }
        } header: {
            SectionHeader(title: "Still works")
        }

        Section {
            ForEach(["New recovery, sleep and strain", "HRV, breathing rate, skin temperature, blood oxygen"], id: \.self) { item in
                Label {
                    Text(item)
                } icon: {
                    Image(systemName: "minus")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            SectionHeader(title: "Paused")
        }
    }
}
