import SwiftUI

/// The sleep stages WHOOP reports totals for, in the order the bar draws them.
enum SleepStage: CaseIterable {
    case awake, rem, light, deep

    var label: String {
        switch self {
        case .awake: "Awake"
        case .rem: "REM"
        case .light: "Light"
        case .deep: "Deep"
        }
    }

    var tint: AnyShapeStyle {
        switch self {
        case .awake: AnyShapeStyle(.tertiary)
        case .rem: AnyShapeStyle(Color.sleepREM)
        case .light: AnyShapeStyle(Color.sleepLight)
        case .deep: AnyShapeStyle(Color.sleepDeep)
        }
    }

    func milli(in sleep: LatestSleepDetail) -> Int64? {
        switch self {
        case .awake: sleep.awakeMs
        case .rem: sleep.remMs
        case .light: sleep.lightMs
        case .deep: sleep.swsMs
        }
    }
}
