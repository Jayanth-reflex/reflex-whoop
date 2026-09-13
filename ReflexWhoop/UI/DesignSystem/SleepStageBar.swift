import SwiftUI

/// Time in each sleep stage, as one bar split by share plus a legend. WHOOP
/// sends totals only, so the bar shows proportions, never a sequence.
struct SleepStageBar: View {
    let sleep: LatestSleepDetail

    private static let barHeight = 14.0
    private static let segmentGap = 3.0

    private let columns = [GridItem(.flexible(), spacing: 22), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Canvas(renderer: draw)
                .frame(height: Self.barHeight)
                .accessibilityHidden(true)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(recordedStages, id: \.self) { stage in
                    LabeledContent {
                        Text(Duration.milliseconds(milli(of: stage)), format: .units(allowed: [.hours, .minutes], width: .narrow))
                            .monospacedDigit()
                    } label: {
                        StatusLabel(text: stage.label, tint: stage.tint)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .font(.subheadline)
        }
    }

    private var recordedStages: [SleepStage] {
        SleepStage.allCases.filter { milli(of: $0) > 0 }
    }

    private func milli(of stage: SleepStage) -> Int64 {
        stage.milli(in: sleep) ?? 0
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let stages = recordedStages
        let total = Double(stages.reduce(0) { $0 + milli(of: $1) })
        var x = 0.0
        for stage in stages {
            let share = Double(milli(of: stage)) / total * size.width
            let gap = stage == stages.last ? 0 : Self.segmentGap
            let segment = CGRect(x: x, y: 0, width: max(share - gap, 2), height: size.height)
            context.fill(Path(roundedRect: segment, cornerRadius: 4), with: .style(stage.tint))
            x += share
        }
    }
}
