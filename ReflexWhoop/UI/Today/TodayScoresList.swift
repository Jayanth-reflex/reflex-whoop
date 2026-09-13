import SwiftUI

/// Today with WHOOP's scores: recovery, strain, last night's sleep and the
/// overnight vitals, each against the person's own normal.
struct TodayScoresList: View {
    let snapshot: TodaySnapshot
    let whoop: SourceState
    let message: String?

    var body: some View {
        List {
            Group {
                if let message {
                    Section {
                        InlineMessage(text: message)
                    }
                }

                Section {
                    NavigationLink(value: Metric.recovery) {
                        RecoveryHero(
                            score: snapshot.value(of: .recovery),
                            usual: snapshot.ranges[.recovery],
                            isIllnessFlagged: snapshot.illnessFlag != nil
                        )
                    }
                    .navigationLinkIndicatorVisibility(.hidden)
                }
                .listRowBackground(Color.clear)

                if let illnessFlag = snapshot.illnessFlag {
                    Section {
                        IllnessCard(signals: illnessFlag.illnessSignals)
                    }
                }

                Section {
                    NavigationLink(value: Metric.strain) {
                        StrainRow(strain: snapshot.value(of: .strain), isToday: snapshot.metrics.day == RecordDAO.dayString(for: .now))
                    }
                    .navigationLinkIndicatorVisibility(.hidden)
                }

                if let sleep = snapshot.sleep {
                    Section {
                        SleepCard(sleep: sleep)
                        NavigationLink(value: Metric.sleepPerformance) {
                            LabeledContent(Metric.sleepPerformance.label) {
                                MetricValueText(metric: .sleepPerformance, value: snapshot.value(of: .sleepPerformance))
                            }
                        }
                    } header: {
                        SectionHeader(title: sleep.isFromLastNight() ? "Last night" : "Latest sleep")
                    }
                }

                Section {
                    ForEach(Metric.Section.overnight.metrics) { metric in
                        NavigationLink(value: metric) {
                            VitalRow(metric: metric, value: snapshot.value(of: metric), range: snapshot.ranges[metric])
                        }
                    }
                } header: {
                    SectionHeader(title: "Overnight vitals")
                } footer: {
                    VStack(alignment: .leading, spacing: 20) {
                        SectionFooter(text: "The band is your normal over the previous \(NormalRange.windowDays) days. The dot is the latest reading.")
                        SourceFooter(lastSyncedAt: snapshot.lastSyncedAt, whoop: whoop)
                    }
                }
            }
            // One modifier for every row; a section's own background (the hero's) wins.
            .listRowBackground(Color.surface)
        }
    }
}
