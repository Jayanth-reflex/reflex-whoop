import SwiftUI

/// One flagged day: its unusual readings, and whether it was flagged for
/// possible illness.
struct UnusualDaySection: View {
    let day: UnusualDay

    var body: some View {
        Section {
            if day.readings.isEmpty, let signals = day.illnessSignals {
                Text("\(IllnessCopy.whatMoved(signals)) \(IllnessCopy.context)")
            }
            ForEach(day.readings) { reading in
                UnusualReadingRow(reading: reading)
            }
        } header: {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: day.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).recordedDay()))
                Spacer()
                if day.illnessSignals != nil {
                    Text("Possible illness")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.sunstone)
                }
            }
        } footer: {
            if let signals = day.illnessSignals {
                SectionFooter(text: day.readings.isEmpty ? IllnessCopy.caveat : "\(IllnessCopy.whatMoved(signals)) \(IllnessCopy.caveat)")
            }
        }
    }
}
