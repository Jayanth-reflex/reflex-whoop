import SwiftUI

/// The app's visual system, in one place so screens compose from it rather than
/// each inventing spacing and color inline.
///
/// Direction: a personal telemetry instrument, not a wellness app. Dark ground,
/// hairline structure, numerals that read like a readout. The one deliberately
/// loud element is the daily verdict — everything else stays quiet so it lands.
enum Theme {
    // MARK: Color

    /// Page ground. Near-black and slightly cool, so the signal colors read as
    /// emitted light rather than paint.
    static let ink = Color(red: 0.027, green: 0.035, blue: 0.043)
    static let surface = Color(red: 0.071, green: 0.090, blue: 0.114)
    static let stroke = Color(red: 0.137, green: 0.169, blue: 0.204)
    static let text = Color(red: 0.902, green: 0.929, blue: 0.953)
    static let muted = Color(red: 0.490, green: 0.541, blue: 0.596)

    /// Physiological signal scale. Also the icon's green, so the app and its
    /// home-screen presence are obviously the same object.
    static let vital = Color(red: 0.0, green: 0.898, blue: 0.627)
    static let caution = Color(red: 1.0, green: 0.761, blue: 0.294)
    static let alert = Color(red: 1.0, green: 0.361, blue: 0.361)

    // MARK: Spacing

    static let gutter: CGFloat = 20
    static let cardPadding: CGFloat = 16
    static let cardRadius: CGFloat = 14

    // MARK: Type

    /// Large readout numerals. Rounded reads as an instrument gauge without
    /// tipping into playfulness, and `monospacedDigit` stops live values from
    /// shifting width as they tick.
    static func readout(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .rounded).monospacedDigit()
    }

    /// Section eyebrow: uppercase and tracked. These carry structure — what
    /// kind of thing you are looking at — rather than decorating it.
    static let eyebrow = Font.system(size: 11, weight: .semibold)
}

// MARK: - Components

/// Uppercase tracked section label. The app's main structural device.
struct Eyebrow: View {
    let text: String
    var tint: Color = Theme.muted

    init(_ text: String, tint: Color = Theme.muted) {
        self.text = text
        self.tint = tint
    }

    var body: some View {
        Text(text.uppercased())
            .font(Theme.eyebrow)
            .tracking(1.2)
            .foregroundStyle(tint)
    }
}

/// Flat card with a hairline edge. Deliberately not `.thinMaterial`: blur over
/// a near-black ground turns to grey mud and washes the signal colors out.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.cardPadding)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )
    }
}

/// A labelled value with an optional confidence note. Every number in this app
/// is supposed to say how much it can be trusted; making that a component
/// rather than an ad-hoc caption is what keeps it consistent.
struct Readout: View {
    let label: String
    let value: String?
    var unit: String?
    var note: String?
    var tint: Color = Theme.text
    var size: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Eyebrow(label)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value ?? "—")
                    .font(Theme.readout(size))
                    .foregroundStyle(value == nil ? Theme.muted : tint)
                if let unit, value != nil {
                    Text(unit)
                        .font(.system(size: size * 0.42, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.muted)
                }
            }
            if let note {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
            }
        }
    }
}

/// Screen scaffold: the dark ground plus consistent gutters, so every screen
/// shares one page shape.
struct ScreenBackground<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Theme.ink.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.gutter) {
                    content
                }
                .padding(Theme.gutter)
            }
        }
    }
}

extension Double {
    /// Shared recovery banding, so the ring, the verdict, and any other reader
    /// cannot drift apart on where "good" starts.
    var recoveryBand: (label: String, color: Color) {
        switch self {
        case 67...: ("High", Theme.vital)
        case 34..<67: ("Moderate", Theme.caution)
        default: ("Low", Theme.alert)
        }
    }
}
