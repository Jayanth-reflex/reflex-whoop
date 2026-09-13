import SwiftUI

/// One About topic, as a short list of plain statements.
struct AboutView: View {
    let topic: AboutTopic

    var body: some View {
        List {
            Section {
                ForEach(topic.points, id: \.self) { point in
                    Text(point)
                        .padding(.vertical, 2)
                }
            }
            .listRowBackground(Color.surface)
        }
        .navigationTitle(topic.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
