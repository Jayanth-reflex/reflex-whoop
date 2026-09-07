import Foundation
import BackgroundTasks

/// Registers and drives the `BGAppRefreshTask` that lets sync run when the app
/// isn't foregrounded. iOS decides if/when this actually fires — typically every
/// few hours at best, sometimes not at all for days — so this is a bonus on top
/// of foreground sync, never the only path data flows through.
enum BackgroundSync {
    static let taskIdentifier = "com.reflexwhoop.sync.refresh"

    /// Call once, early in app launch (before `applicationDidFinishLaunching`
    /// returns in UIKit terms — here, before the SwiftUI `App`'s body is first
    /// evaluated matters less than "before the task could plausibly fire", which
    /// in practice means from the `App`'s `init`).
    static func register(container: AppContainer) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            handle(task as! BGAppRefreshTask, container: container)
        }
    }

    /// Schedules the next opportunistic run. Call after every successful sync
    /// (foreground or background) so there's always one pending.
    static func scheduleNext() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(4 * 60 * 60) // no earlier than 4h out
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGAppRefreshTask, container: AppContainer) {
        scheduleNext() // always queue the next one, whether or not this one succeeds

        let syncTask = Task {
            do {
                guard let engine = await container.syncEngine() else {
                    task.setTaskCompleted(success: false)
                    return
                }
                _ = try await engine.syncNow(trigger: "background")
                task.setTaskCompleted(success: true)
            } catch {
                task.setTaskCompleted(success: false)
            }
        }

        task.expirationHandler = {
            syncTask.cancel()
        }
    }
}
