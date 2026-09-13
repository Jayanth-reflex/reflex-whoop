import SwiftUI

extension RecoveryBand {
    var tint: Color {
        switch self {
        case .low: .garnet
        case .moderate: .amber
        case .high: .jade
        }
    }
}
