import SwiftUI

extension SourceState {
    /// The WHOOP account's state in plain words.
    var statusText: String {
        switch self {
        case .active: "Connected"
        case .notConfigured: "Not set up"
        case .unauthorized: "Signed out"
        case .inactive: "Membership ended"
        case .unreachable: "Can't reach WHOOP"
        }
    }

    var tint: AnyShapeStyle {
        switch self {
        case .active: AnyShapeStyle(Color.jade)
        case .inactive, .unreachable: AnyShapeStyle(Color.sunstone)
        case .notConfigured, .unauthorized: AnyShapeStyle(.tertiary)
        }
    }
}
