import XCTest
@testable import ReflexWhoop

/// Exercises the real Keychain (works fine in the Simulator) rather than mocking
/// it — the atomicity guarantee this type exists for (see its header comment) is
/// only real if `saveTokens` genuinely round-trips through Keychain, not a fake.
final class TokenStoreTests: XCTestCase {
    override func tearDownWithError() throws {
        try TokenStore.clearAll()
    }

    func testTokensRoundTripThroughKeychain() throws {
        let tokens = TokenSet(accessToken: "access-123", refreshToken: "refresh-456", expiresAt: Date().addingTimeInterval(3600))
        try TokenStore.saveTokens(tokens)

        let loaded = try TokenStore.loadTokens()
        XCTAssertEqual(loaded?.accessToken, "access-123")
        XCTAssertEqual(loaded?.refreshToken, "refresh-456")
    }

    func testSavingNewTokensReplacesOldOnes() throws {
        try TokenStore.saveTokens(TokenSet(accessToken: "old", refreshToken: "old-r", expiresAt: Date()))
        try TokenStore.saveTokens(TokenSet(accessToken: "new", refreshToken: "new-r", expiresAt: Date()))

        let loaded = try TokenStore.loadTokens()
        XCTAssertEqual(loaded?.accessToken, "new", "rotation must replace, not accumulate")
    }

    func testClearTokensRemovesThem() throws {
        try TokenStore.saveTokens(TokenSet(accessToken: "a", refreshToken: "b", expiresAt: Date()))
        try TokenStore.clearTokens()
        XCTAssertNil(try TokenStore.loadTokens())
    }

    func testLoadingWithNothingSavedReturnsNil() throws {
        XCTAssertNil(try TokenStore.loadTokens())
    }

    func testClientCredentialsRoundTrip() throws {
        try TokenStore.saveClientCredentials(clientID: "client-abc", clientSecret: "secret-xyz")
        let loaded = try TokenStore.loadClientCredentials()
        XCTAssertEqual(loaded?.clientID, "client-abc")
        XCTAssertEqual(loaded?.clientSecret, "secret-xyz")
    }

    func testClearAllRemovesTokensAndCredentials() throws {
        try TokenStore.saveTokens(TokenSet(accessToken: "a", refreshToken: "b", expiresAt: Date()))
        try TokenStore.saveClientCredentials(clientID: "c", clientSecret: "s")
        try TokenStore.clearAll()
        XCTAssertNil(try TokenStore.loadTokens())
        XCTAssertNil(try TokenStore.loadClientCredentials())
    }

    func testIsExpiredRespectsSixtySecondSafetyMargin() {
        let almostExpired = TokenSet(accessToken: "a", refreshToken: "b", expiresAt: Date().addingTimeInterval(30))
        XCTAssertTrue(almostExpired.isExpired, "a token expiring in 30s must be treated as already expired")

        let freshEnough = TokenSet(accessToken: "a", refreshToken: "b", expiresAt: Date().addingTimeInterval(300))
        XCTAssertFalse(freshEnough.isExpired)
    }
}
