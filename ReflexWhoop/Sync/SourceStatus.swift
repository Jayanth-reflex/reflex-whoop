import Foundation
import GRDB

/// What a data source is currently able to give us, as a first-class state
/// rather than an error path — docs/ADR-001-data-sovereignty.md's third
/// commitment: "every source can be absent."
///
/// The distinction that matters is `inactive` vs `unreachable`. A lapsed WHOOP
/// membership and a dropped wifi connection both stop new data arriving, but
/// one is permanent-until-you-act and the other fixes itself. Showing the same
/// red error for both is how an app ends up looking broken when it is in fact
/// working exactly as designed on a complete local archive.
enum SourceState: Equatable {
    /// Configured, authorized, and last contact succeeded.
    case active(lastSuccess: Date?)
    /// Never configured — no credentials have been entered.
    case notConfigured
    /// Configured but signed out, or the refresh token is gone.
    case unauthorized
    /// Authorized, but the account isn't entitled to the data. What a lapsed
    /// membership looks like. The archive stays valid; nothing new arrives.
    case inactive(reason: String)
    /// Transient: network down, WHOOP down, rate limit exhausted.
    case unreachable(reason: String)

    /// True when this source can still contribute new data.
    var canCollect: Bool {
        switch self {
        case .active, .unreachable: true
        case .notConfigured, .unauthorized, .inactive: false
        }
    }
}

/// How much history the local archive holds, independent of whether any source
/// is currently reachable. This is the number that stays true when everything
/// else stops working.
struct ArchiveSummary: Equatable {
    let firstDay: String?
    let lastDay: String?
    let dayCount: Int
    let bleSessionCount: Int
    let bleSampleCount: Int

    var isEmpty: Bool { dayCount == 0 && bleSessionCount == 0 }
}

enum SourceStatus {
    /// Classifies the WHOOP API source. Auth state is passed in rather than
    /// read here because it lives behind an actor and in the Keychain, not in
    /// the database.
    static func whoop(_ db: GRDB.Database, isSignedIn: Bool, hasCredentials: Bool) throws -> SourceState {
        guard hasCredentials else { return .notConfigured }
        guard isSignedIn else { return .unauthorized }

        let row = try Row.fetchOne(
            db,
            sql: """
            SELECT finished_at, error, error_kind FROM sync_log
            WHERE finished_at IS NOT NULL ORDER BY id DESC LIMIT 1
            """
        )
        guard let row else { return .active(lastSuccess: nil) }

        let errorKind: String? = row["error_kind"]
        let error: String? = row["error"]
        let finishedAt: Int64? = row["finished_at"]

        if errorKind == SyncErrorKind.forbidden.rawValue {
            return .inactive(reason: "WHOOP returned 403 for your data. Usually means the membership lapsed. The archive below is unaffected.")
        }
        if let error {
            return .unreachable(reason: error)
        }
        return .active(lastSuccess: finishedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) })
    }

    /// The band source. There is no persistent pairing to interrogate — a
    /// session either happened or didn't — so this reports on recorded history
    /// rather than live connectivity, which `BandConnection.state` already owns.
    static func band(_ db: GRDB.Database) throws -> SourceState {
        let lastSession = try Int64.fetchOne(db, sql: "SELECT MAX(started_at) FROM ble_sessions")
        guard let lastSession else { return .notConfigured }
        return .active(lastSuccess: Date(timeIntervalSince1970: TimeInterval(lastSession)))
    }

    static func archive(_ db: GRDB.Database) throws -> ArchiveSummary {
        let dayRow = try Row.fetchOne(
            db, sql: "SELECT MIN(day) AS first_day, MAX(day) AS last_day, COUNT(*) AS n FROM daily_metrics"
        )
        let sessionCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ble_sessions") ?? 0
        let sampleCount = try Int.fetchOne(db, sql: "SELECT COALESCE(SUM(hr_sample_count), 0) FROM session_metrics") ?? 0

        return ArchiveSummary(
            firstDay: dayRow?["first_day"],
            lastDay: dayRow?["last_day"],
            dayCount: dayRow?["n"] ?? 0,
            bleSessionCount: sessionCount,
            bleSampleCount: sampleCount
        )
    }
}

/// Stored in `sync_log.error_kind` so a later read can classify a failure
/// without string-matching a localized message.
enum SyncErrorKind: String {
    case forbidden
    case unauthorized
    case transport
    case other

    static func classify(_ error: Error) -> SyncErrorKind {
        if let clientError = error as? WhoopClient.ClientError {
            switch clientError {
            case .forbidden: return .forbidden
            case .http(let status, _): return status == 401 ? .unauthorized : .other
            case .invalidResponse: return .transport
            }
        }
        if error is URLError { return .transport }
        return .other
    }
}
