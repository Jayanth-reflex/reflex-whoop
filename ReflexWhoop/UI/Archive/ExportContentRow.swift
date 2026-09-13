import SwiftUI

/// One kind of file in an export, with its format.
struct ExportContentRow: View {
    let title: String
    let systemImage: String
    let format: String

    var body: some View {
        LabeledContent {
            Text(format)
        } label: {
            Label(title, systemImage: systemImage)
        }
    }
}
