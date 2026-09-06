import Foundation
import GRDB
@testable import ReflexWhoop

enum TestSupport {
    /// A fresh on-disk database at a unique temp path, migrated and ready to use.
    /// On-disk (not `:memory:`) because `DatabasePool` — which the real app and
    /// `Database` use — requires a file for its multi-connection WAL setup.
    static func makeDatabase() throws -> ReflexWhoop.Database {
        let path = NSTemporaryDirectory() + "reflexwhoop-test-\(UUID().uuidString).sqlite"
        return try ReflexWhoop.Database(path: path)
    }

    static func loadFixture(_ name: String) throws -> Data {
        guard let url = Bundle(for: FixtureBundleAnchor.self).url(forResource: name, withExtension: "json") else {
            throw FixtureError.notFound(name)
        }
        return try Data(contentsOf: url)
    }

    enum FixtureError: Error {
        case notFound(String)
    }
}

/// Anchor class purely so `Bundle(for:)` resolves to the test target's bundle
/// (where the Fixtures/*.json resources are copied).
private final class FixtureBundleAnchor {}
