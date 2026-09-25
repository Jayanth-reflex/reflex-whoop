import XCTest
@testable import ReflexWhoop

/// WHOOP rotates the refresh token on every use, so two refreshes that overlap
/// spend the same token twice: the loser gets a 400 and, if both somehow land,
/// one of the two rotated tokens is orphaned and the next refresh fails for good.
/// `WhoopAuth` is an actor, which is not enough on its own — it yields its
/// executor at every `await`, so both callers can pass the expiry check before
/// either finishes its request.
///
/// These tests drive the real actor through a stubbed `URLSession` and count what
/// reaches the token endpoint.
final class WhoopAuthRefreshTests: XCTestCase {
    private var session: URLSession!

    override func setUpWithError() throws {
        try TokenStore.saveClientCredentials(clientID: "client-abc", clientSecret: "secret-xyz")
        TokenEndpointStub.reset()

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TokenEndpointStub.self]
        session = URLSession(configuration: configuration)
    }

    override func tearDownWithError() throws {
        try TokenStore.clearAll()
        TokenEndpointStub.reset()
        session = nil
    }

    /// The race seen on the phone: sync_log 118 and 119 started in the same second,
    /// one succeeded and the other failed the token exchange.
    func testConcurrentRefreshesSpendTheRefreshTokenOnce() async throws {
        try TokenStore.saveTokens(expiredTokens())
        let auth = WhoopAuth(urlSession: session)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<4 {
                group.addTask { try await auth.forceRefresh() }
            }
            try await group.waitForAll()
        }

        XCTAssertEqual(TokenEndpointStub.requestCount, 1,
                       "four overlapping refreshes must reach WHOOP once — the rotating token can only be spent once")
    }

    /// Every caller still ends up with the token the one request returned.
    func testCallersJoiningAnInFlightRefreshGetTheNewToken() async throws {
        try TokenStore.saveTokens(expiredTokens())
        let auth = WhoopAuth(urlSession: session)

        try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<3 {
                group.addTask { try await auth.validAccessToken() }
            }
            for try await token in group {
                XCTAssertEqual(token, TokenEndpointStub.issuedAccessToken)
            }
        }
        XCTAssertEqual(TokenEndpointStub.requestCount, 1)
    }

    /// A refresh that fails must not be remembered as one that succeeded: the next
    /// caller has to be free to try again.
    func testAFailedRefreshDoesNotBlockTheNextAttempt() async throws {
        try TokenStore.saveTokens(expiredTokens())
        let auth = WhoopAuth(urlSession: session)

        TokenEndpointStub.nextResponseIsFailure = true
        do {
            try await auth.forceRefresh()
            XCTFail("expected the stubbed 400 to surface")
        } catch {}

        try await auth.forceRefresh()
        XCTAssertEqual(TokenEndpointStub.requestCount, 2, "the second attempt must reach WHOOP, not reuse the failure")
    }

    /// An unexpired token needs no request at all.
    func testRefreshIfNeededDoesNothingWhileTheTokenIsValid() async throws {
        try TokenStore.saveTokens(TokenSet(accessToken: "still-good", refreshToken: "r", expiresAt: Date().addingTimeInterval(3600)))
        let auth = WhoopAuth(urlSession: session)

        try await auth.refreshIfNeeded()

        XCTAssertEqual(TokenEndpointStub.requestCount, 0)
    }

    private func expiredTokens() -> TokenSet {
        TokenSet(accessToken: "expired-access", refreshToken: "rotating-refresh", expiresAt: Date().addingTimeInterval(-60))
    }
}

/// Stands in for WHOOP's token endpoint. Counts requests and holds each one long
/// enough that a second caller would overlap it if nothing serialized them.
private final class TokenEndpointStub: URLProtocol {
    static let issuedAccessToken = "rotated-access"

    private static let lock = NSLock()
    private static var requests = 0
    nonisolated(unsafe) static var nextResponseIsFailure = false

    static var requestCount: Int {
        lock.lock(); defer { lock.unlock() }
        return requests
    }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        requests = 0
        nextResponseIsFailure = false
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url == OAuthConfig.tokenURL
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.requests += 1
        let fail = Self.nextResponseIsFailure
        Self.nextResponseIsFailure = false
        Self.lock.unlock()

        // Wide enough that an unserialized second caller is certain to overlap.
        Thread.sleep(forTimeInterval: 0.2)

        let status = fail ? 400 : 200
        let body = fail
            ? Data(#"{"error":"invalid_request"}"#.utf8)
            : Data(#"{"access_token":"rotated-access","refresh_token":"rotated-refresh","expires_in":3600}"#.utf8)
        let response = HTTPURLResponse(url: OAuthConfig.tokenURL, statusCode: status, httpVersion: nil, headerFields: nil)!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
