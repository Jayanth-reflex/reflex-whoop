import SwiftUI

/// The segmented 30D / 90D / 1Y / All control above a history.
struct HistoryRangePicker: View {
    @Binding var selection: HistoryRange

    var body: some View {
        Picker("Range", selection: $selection) {
            ForEach(HistoryRange.allCases) { range in
                Text(range.label).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}
