import Foundation
import Observation

/// Composition root. Owns every long-lived service and hands them to views via
/// the SwiftUI environment. Phase 1 only wires up storage; Auth/Sync/Ble/Analysis
/// services are added here as their phases land, not scattered across views.
@Observable
final class AppContainer {
    let database: Database

    init() throws {
        database = try Database(path: try Database.defaultPath())
    }
}
