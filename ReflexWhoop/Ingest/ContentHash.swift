import Foundation
import CryptoKit

/// A stable hash of a record's normalized fields, used to detect whether a re-fetched
/// record actually changed. With a 7-day lookback on every incremental sync, most
/// re-fetched records are byte-identical — `content_hash` lets the DAO skip both the
/// write and the `dirty_days` mark for the ~95% that didn't change, which is what
/// makes the lookback overlap nearly free.
///
/// Callers build the input as `field1|field2|field3...` in a fixed, documented order
/// (see each DAO's `contentHash` computation) — order must never change without also
/// accepting that every existing row will look "changed" once, harmlessly.
enum ContentHash {
    static func compute(_ parts: [CustomStringConvertible?]) -> String {
        let joined = parts.map { $0.map(String.init(describing:)) ?? "∅" }.joined(separator: "|")
        let digest = SHA256.hash(data: Data(joined.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
