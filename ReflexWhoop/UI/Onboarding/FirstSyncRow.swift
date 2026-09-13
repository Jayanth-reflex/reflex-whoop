import SwiftUI

/// One kind of WHOOP record during the first sync: waiting, then its count.
struct FirstSyncRow: View {
    let title: String
    let count: Int?
    let noun: String
    let isSyncing: Bool

    var body: some View {
        LabeledContent {
            if let count {
                Text("\(count.formatted()) \(noun)")
            } else if isSyncing {
                ProgressView()
            }
        } label: {
            Label {
                Text(title)
            } icon: {
                Image(systemName: count == nil ? "clock" : "checkmark")
                    .foregroundStyle(count == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.jade))
            }
        }
    }
}
