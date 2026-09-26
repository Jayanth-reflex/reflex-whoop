import Foundation
import BackgroundTasks

/// Runs `Database.compact()` in a `BGProcessingTask` that waits for the phone to be on
/// power. The first compaction is a full VACUUM: it rewrites the whole file and blocks
/// the database while it runs, which on launch would stall the app for seconds and risk
/// the launch watchdog. On the charger, usually overnight, it costs nothing anyone sees.
///
/// Processing tasks need the `processing` background mode, not an entitlement, so this
/// works on a free Apple ID.
enum DatabaseMaintenance {
    static let taskIdentifier = "com.reflexwhoop.maintenance"

    /// Call from the `App`'s `init`, for the same reason as `BackgroundSync.register`:
    /// a background launch to run the task no-ops if the handler isn't registered yet.
    static func register(database: Database) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            handle(task as! BGProcessingTask, database: database)
        }
    }

    /// Keeps one run pending. No earliest date: submitting replaces the pending request,
    /// so a date would slide forward on every launch and never arrive for someone who
    /// opens the app daily. iOS picks the moment once the phone is charging.
    static func schedule() {
        let request = BGProcessingTaskRequest(identifier: taskIdentifier)
        request.requiresExternalPower = true
        request.requiresNetworkConnectivity = false
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGProcessingTask, database: Database) {
        schedule()
        let work = Task.detached(priority: .background) {
            do {
                try await database.compact()
                task.setTaskCompleted(success: true)
            } catch {
                task.setTaskCompleted(success: false)
            }
        }
        // VACUUM is one blocking SQLite call that Swift cancellation can't reach, so
        // interrupt SQLite itself when iOS wants its time back. An interrupted VACUUM
        // rolls back, leaving the file exactly as it was.
        task.expirationHandler = {
            database.dbPool.interrupt()
            work.cancel()
        }
    }
}
