import Foundation

/// WHOOP v2's per-record scoring state. Records are created unscored and filled in
/// later; sleep records are also retroactively re-scored after the fact. Sync logic
/// depends on this: `PENDING_SCORE` records go into `pending_scores` for re-fetch.
enum ScoreState: String, Codable {
    case scored = "SCORED"
    case pendingScore = "PENDING_SCORE"
    case unscorable = "UNSCORABLE"
}

/// WHOOP's paginated collection envelope: `{ "records": [...], "next_token": "..." }`.
/// An empty/absent `next_token` means the caller has reached the last page.
struct PaginatedResponse<T: Decodable>: Decodable {
    let records: [T]
    let nextToken: String?

    enum CodingKeys: String, CodingKey {
        case records
        case nextToken = "next_token"
    }
}

enum WhoopDateFormatter {
    /// WHOOP timestamps are ISO 8601 UTC with millisecond fractional seconds,
    /// e.g. "2022-04-24T11:25:44.774Z". `ISO8601DateFormatter` with
    /// `.withFractionalSeconds` handles this; ` Date`'s default `Decodable`
    /// conformance does not, so every model decodes dates through this formatter
    /// via a custom `init(from:)` rather than relying on `JSONDecoder.dateDecodingStrategy`.
    static let shared: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// A handful of WHOOP fields (rarely) omit fractional seconds; fall back gracefully
    /// rather than failing the whole decode over a formatting quirk in one field.
    static let fallback: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ string: String) -> Date? {
        shared.date(from: string) ?? fallback.date(from: string)
    }
}

/// Decodes a WHOOP timestamp string field into a `Date`, via `WhoopDateFormatter`.
/// Use as `try container.decode(WhoopDate.self, forKey: .start).date`.
struct WhoopDate: Decodable {
    let date: Date

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let parsed = WhoopDateFormatter.parse(raw) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unparseable WHOOP date: \(raw)"
            )
        }
        date = parsed
    }
}

/// Same as `WhoopDate` but for fields that are `null` while a cycle is still ongoing
/// (e.g. `cycle.end`).
struct WhoopOptionalDate: Decodable {
    let date: Date?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            date = nil
            return
        }
        let raw = try container.decode(String.self)
        date = WhoopDateFormatter.parse(raw)
    }
}
