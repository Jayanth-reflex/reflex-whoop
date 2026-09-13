import XCTest
@testable import ReflexWhoop

final class CollectionSettingsTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "continuousBleCollection")
        super.tearDown()
    }

    /// Off unless explicitly turned on: holding a BLE connection open costs
    /// battery on the phone and the band, and must not start because someone
    /// launched the app.
    func testDefaultsToOff() {
        UserDefaults.standard.removeObject(forKey: "continuousBleCollection")
        XCTAssertFalse(CollectionSettings.continuousCollectionEnabled)
    }

    func testPersistsAcrossReads() {
        CollectionSettings.continuousCollectionEnabled = true
        XCTAssertTrue(CollectionSettings.continuousCollectionEnabled)
        CollectionSettings.continuousCollectionEnabled = false
        XCTAssertFalse(CollectionSettings.continuousCollectionEnabled)
    }
}

@MainActor
final class BandConnectionReconnectTests: XCTestCase {
    /// `disconnect()` is explicit user intent to stop, so it must clear
    /// auto-reconnect — otherwise "stop" would immediately re-dial.
    func testDisconnectClearsAutoReconnect() {
        let connection = BandConnection()
        connection.autoReconnect = true
        connection.disconnect()
        XCTAssertFalse(connection.autoReconnect)
    }

    func testStartingContinuousSessionEnablesAutoReconnect() throws {
        let database = try TestSupport.makeDatabase()
        let recorder = SpikeRecorder(dbPool: database.dbPool)
        try recorder.startContinuousSession()
        XCTAssertTrue(recorder.connection.autoReconnect)
        XCTAssertNotNil(recorder.sessionID)
    }

    /// A plain Live-screen spike must not ask iOS to relaunch the app for BLE
    /// events, so it stays a foreground-only connection.
    func testPlainSessionDoesNotEnableAutoReconnect() throws {
        let database = try TestSupport.makeDatabase()
        let recorder = SpikeRecorder(dbPool: database.dbPool)
        try recorder.startSession()
        XCTAssertFalse(recorder.connection.autoReconnect)
    }
}
