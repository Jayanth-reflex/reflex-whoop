import Foundation

/// Whether the app records from the band: holds the connection open,
/// reconnects by itself, and keeps going in the background.
///
/// This exists for the case docs/ADR-001-data-sovereignty.md is about: when the
/// WHOOP cloud source stops producing data, the band is the only source left,
/// and a source that only records while you are staring at it is not a source.
///
/// Off by default and deliberately opt-in. Holding a BLE connection open and
/// streaming ~1 sample/second costs battery on both the phone and the band, and
/// silently starting that on someone's behalf because they launched an app is
/// not a decision to make for them.
enum CollectionSettings {
    /// Public so a view can observe the setting with `@AppStorage`.
    static let continuousKey = "continuousBleCollection"

    static var continuousCollectionEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: continuousKey) }
        set { UserDefaults.standard.set(newValue, forKey: continuousKey) }
    }
}
