import Foundation

/// Thin authenticated HTTP client over the WHOOP v2 API. Deliberately returns raw
/// `Data`, never decoded models — decoding only happens in `ApiNormalizer`, after
/// the bytes are safely in `ingest_inbox`. `WhoopClient`'s job stops at "get me
/// these bytes, authenticated, rate-limited, retried."
actor WhoopClient {
    enum ClientError: LocalizedError {
        case http(status: Int, body: String)
        /// The token authenticated fine but the account isn't entitled to the
        /// data — which is what a lapsed membership looks like from here.
        /// Separated from `.http` because the app's response is different in
        /// kind: not "retry later", but "this source is inactive, fall back to
        /// the archive" (see `SourceStatus`, docs/ADR-001-data-sovereignty.md).
        ///
        /// Mapped from HTTP 403. Not verified against a genuinely lapsed
        /// account — no such account has been available to test with — so
        /// treat the mapping as the best available signal rather than a
        /// confirmed fact.
        case forbidden(body: String)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .http(let status, let body): "WHOOP API error \(status): \(body.prefix(500))"
            case .forbidden(let body): "WHOOP denied access to this data (403): \(body.prefix(500))"
            case .invalidResponse: "Non-HTTP response from WHOOP API"
            }
        }
    }

    static let baseURL = URL(string: "https://api.prod.whoop.com/developer")!

    private let auth: WhoopAuth
    private let rateLimiter: RateLimiter
    private let urlSession: URLSession
    private let maxRetries = 5

    init(auth: WhoopAuth, rateLimiter: RateLimiter = RateLimiter(), urlSession: URLSession = .shared) {
        self.auth = auth
        self.rateLimiter = rateLimiter
        self.urlSession = urlSession
    }

    // MARK: - Named endpoints (all per docs/design.md's Source A table)

    func cyclePage(nextToken: String?, start: Date?, end: Date?, limit: Int = 25) async throws -> Data {
        try await get("/v2/cycle", query: pageQuery(nextToken: nextToken, start: start, end: end, limit: limit))
    }

    func singleCycle(id: String) async throws -> Data {
        try await get("/v2/cycle/\(id)", query: [])
    }

    func recoveryPage(nextToken: String?, start: Date?, end: Date?, limit: Int = 25) async throws -> Data {
        try await get("/v2/recovery", query: pageQuery(nextToken: nextToken, start: start, end: end, limit: limit))
    }

    func singleRecovery(forCycleID cycleID: String) async throws -> Data {
        try await get("/v2/cycle/\(cycleID)/recovery", query: [])
    }

    func sleepPage(nextToken: String?, start: Date?, end: Date?, limit: Int = 25) async throws -> Data {
        try await get("/v2/activity/sleep", query: pageQuery(nextToken: nextToken, start: start, end: end, limit: limit))
    }

    func singleSleep(id: String) async throws -> Data {
        try await get("/v2/activity/sleep/\(id)", query: [])
    }

    func workoutPage(nextToken: String?, start: Date?, end: Date?, limit: Int = 25) async throws -> Data {
        try await get("/v2/activity/workout", query: pageQuery(nextToken: nextToken, start: start, end: end, limit: limit))
    }

    func singleWorkout(id: String) async throws -> Data {
        try await get("/v2/activity/workout/\(id)", query: [])
    }

    func profile() async throws -> Data {
        try await get("/v2/user/profile/basic", query: [])
    }

    func bodyMeasurement() async throws -> Data {
        try await get("/v2/user/measurement/body", query: [])
    }

    /// Revokes the app's access token server-side. Best-effort: callers should
    /// clear local tokens regardless of whether this succeeds — a personal app's
    /// sign-out shouldn't be blocked by a network call.
    func revokeAccess() async throws {
        _ = try await request(path: "/v2/user/access", method: "DELETE", query: [])
    }

    // MARK: - Core request plumbing

    private func pageQuery(nextToken: String?, start: Date?, end: Date?, limit: Int) -> [URLQueryItem] {
        var items = [URLQueryItem(name: "limit", value: String(limit))]
        if let nextToken { items.append(URLQueryItem(name: "nextToken", value: nextToken)) }
        if let start { items.append(URLQueryItem(name: "start", value: Self.iso8601.string(from: start))) }
        if let end { items.append(URLQueryItem(name: "end", value: Self.iso8601.string(from: end))) }
        return items
    }

    private func get(_ path: String, query: [URLQueryItem]) async throws -> Data {
        try await request(path: path, method: "GET", query: query)
    }

    @discardableResult
    private func request(path: String, method: String, query: [URLQueryItem], attempt: Int = 1) async throws -> Data {
        await rateLimiter.acquire()

        let accessToken = try await auth.validAccessToken()
        var components = URLComponents(url: Self.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }

        var urlRequest = URLRequest(url: components.url!)
        urlRequest.httpMethod = method
        urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }

        await rateLimiter.recordHeaders(
            remaining: http.value(forHTTPHeaderField: "X-RateLimit-Remaining").flatMap(Int.init),
            resetSeconds: http.value(forHTTPHeaderField: "X-RateLimit-Reset").flatMap(Int.init)
        )

        switch http.statusCode {
        case 200..<300:
            return data

        case 401 where attempt == 1:
            // Access token was rejected despite our local expiry estimate saying
            // it was still valid — force a refresh (server clock may have drifted
            // from ours, or the token was revoked and re-issued) and retry once.
            try await auth.forceRefresh()
            return try await request(path: path, method: method, query: query, attempt: attempt + 1)

        case 403:
            throw ClientError.forbidden(body: String(data: data, encoding: .utf8) ?? "")

        case 429 where attempt <= maxRetries:
            let resetSeconds = http.value(forHTTPHeaderField: "X-RateLimit-Reset").flatMap(Int.init)
            await rateLimiter.handleRateLimitExceeded(resetSeconds: resetSeconds)
            return try await request(path: path, method: method, query: query, attempt: attempt + 1)

        case 500..<600 where attempt <= maxRetries:
            let backoff = min(pow(2.0, Double(attempt)), 30.0)
            try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
            return try await request(path: path, method: method, query: query, attempt: attempt + 1)

        default:
            throw ClientError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
    }

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
