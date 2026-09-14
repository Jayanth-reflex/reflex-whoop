import Foundation
import GRDB

/// What Today reads from the database: the latest scored day and the band's
/// heart rate since `start`.
struct TodayReadings {
    let snapshot: TodaySnapshot?
    let heartRateToday: HeartRateSpan

    static func load(_ db: GRDB.Database, since start: Date) throws -> TodayReadings {
        TodayReadings(snapshot: try TodaySnapshot.load(db), heartRateToday: try RecordingQueries.heartRate(db, since: start))
    }

    /// Fresh readings whenever a table they come from changes, so scores from
    /// a sync that finishes after Today appeared show up by themselves.
    static func observation(since start: Date) -> ValueObservation<ValueReducers.Fetch<TodayReadings>> {
        ValueObservation.tracking { db in try load(db, since: start) }
    }
}
