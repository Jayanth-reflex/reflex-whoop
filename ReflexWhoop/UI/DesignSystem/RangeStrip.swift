import SwiftUI

/// A reading against the person's normal: a track, the normal range as a
/// band, and the reading as a dot that turns sunstone once it's unusual.
/// No band without a range, and no dot without a reading and a range to place
/// it against.
///
/// Hidden from VoiceOver: the row showing it states the value and status.
struct RangeStrip: View {
    let value: Double?
    let range: NormalRange?

    @Environment(\.colorSchemeContrast) private var contrast

    /// The strip spans this many standard deviations either side of the mean,
    /// so an unusual reading (2 SD) still lands clear of the ends.
    private static let spread = 3.2
    private static let trackHeight = 6.0
    private static let dotRadius = 5.5
    /// A ring in the row's own colour, so the dot reads as sitting on the band.
    private static let ringWidth = 2.5

    var body: some View {
        Canvas { context, size in
            let midY = size.height / 2
            let track = CGRect(x: 0, y: midY - Self.trackHeight / 2, width: size.width, height: Self.trackHeight)
            // Increase Contrast lifts the band and track apart to 3:1 or more.
            let isIncreased = contrast == .increased
            context.fill(Capsule().path(in: track), with: isIncreased ? .style(.quaternary) : .style(.quinary))

            guard let range, range.standardDeviation > 0 else { return }
            let spread = Self.spread * range.standardDeviation
            let scale = HorizontalScale(
                domain: (range.mean - spread)...(range.mean + spread),
                inset: Self.dotRadius + Self.ringWidth,
                width: size.width
            )
            let bandStart = scale.x(range.lowerBound)
            let band = CGRect(
                x: bandStart,
                y: track.minY,
                width: max(scale.x(range.upperBound) - bandStart, Self.trackHeight),
                height: Self.trackHeight
            )
            context.fill(Capsule().path(in: band), with: isIncreased ? .style(.secondary) : .style(.tertiary))

            guard let value else { return }
            let centre = CGPoint(x: scale.x(value), y: midY)
            let isUnusual = ReadingStatus.classify(value, against: range).isUnusual
            context.fill(Path(circleAround: centre, radius: Self.dotRadius + Self.ringWidth), with: .color(.surface))
            context.fill(Path(circleAround: centre, radius: Self.dotRadius), with: isUnusual ? .color(.sunstone) : .style(.primary))
        }
        .frame(height: 16)
        .accessibilityHidden(true)
    }
}
