import SwiftUI

/// Today without WHOOP scores: the band's heart rate so far today. After a
/// membership ends it also says so, and lists the last scores as history
/// rather than presenting them as today.
struct TodayBandList: View {
    let content: TodayContent
    let membershipEnded: Bool
    let message: String?

    var body: some View {
        List {
            Group {
                if let message {
                    Section {
                        InlineMessage(text: message)
                    }
                }

                if membershipEnded {
                    Section {
                        MembershipEndedCard(archive: content.sources.archive)
                    }
                }

                Section {
                    HeartRateTodayCard(span: content.heartRateToday)
                    if !content.heartRateToday.readings.isEmpty {
                        LabeledContent("Recorded") {
                            Text(Duration.seconds(content.heartRateToday.readings.count * 60), format: .units(allowed: [.hours, .minutes], width: .narrow))
                        }
                    }
                } header: {
                    SectionHeader(title: "Heart rate today")
                } footer: {
                    SectionFooter(text: "From your band. Heart rate from while the band is away isn't recorded.")
                }

                if membershipEnded, let snapshot = content.snapshot {
                    Section {
                        LastScoresRows(snapshot: snapshot)
                    } header: {
                        SectionHeader(title: "Not available without WHOOP")
                    } footer: {
                        SectionFooter(text: "HRV and sleep need the band's other signals decoded, which isn't done yet. They'll appear here once that works, never as estimates.")
                    }
                }
            }
            .listRowBackground(Color.surface)
        }
    }
}
