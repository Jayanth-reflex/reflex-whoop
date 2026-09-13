import SwiftUI

/// What the account has brought in so far.
struct WhoopHistorySection: View {
    let history: WhoopHistory

    var body: some View {
        Section {
            LabeledContent("Recovery and HRV", value: "\(history.recoveryDays.formatted()) days")
            LabeledContent("Sleep", value: "\(history.sleepNights.formatted()) nights")
            LabeledContent("Strain and workouts", value: "\(history.strainDays.formatted()) days")
        } header: {
            SectionHeader(title: "Brings in")
        }
    }
}
