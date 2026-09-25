import Foundation
import AuthenticationServices
import CryptoKit
#if canImport(UIKit)
import UIKit
#endif

/// Drives the WHOOP OAuth2 authorization-code flow and keeps the access token
/// fresh.
///
/// WHOOP rotates the refresh token on every use, so two refreshes must never be
/// outstanding at once: the second spends a token the first already invalidated,
/// which fails, and if both somehow land then one of the two rotated tokens is
/// orphaned and the next refresh has nothing valid to send — no way back short of
/// a full re-login.
///
/// Being an `actor` does not achieve that on its own. An actor yields its executor
/// at every `await`, so two callers can both pass the expiry check and both start a
/// request while the first is suspended in `URLSession`. `refreshOnce()` is what
/// actually serializes them, by holding the one in-flight refresh for later callers
/// to await.
actor WhoopAuth {
    enum AuthError: LocalizedError {
        case missingCredentials
        case stateMismatch
        case missingCode(URL)
        case tokenExchangeFailed(status: Int, body: String)
        case notAuthenticated
        case presentationFailed

        var errorDescription: String? {
            switch self {
            case .missingCredentials: "No WHOOP client ID or secret saved yet. Add them in Archive › WHOOP account."
            case .stateMismatch: "OAuth state mismatch — possible tampering, login aborted."
            case .missingCode(let url): "No authorization code in callback: \(url.absoluteString)"
            case .tokenExchangeFailed(let status, let body): "Token exchange failed (\(status)): \(body)"
            case .notAuthenticated: "Not signed in to WHOOP."
            case .presentationFailed: "Could not present the WHOOP login screen."
            }
        }
    }

    private let urlSession: URLSession

    /// Non-nil while a refresh is outstanding. See `refreshOnce()`.
    private var refreshInFlight: Task<Void, Error>?

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    /// True once *some* tokens exist locally. Does not imply they're still valid —
    /// callers that need a guaranteed-fresh token should go through
    /// `validAccessToken()`, which refreshes first.
    func isSignedIn() throws -> Bool {
        try TokenStore.loadTokens() != nil
    }

    /// Runs the full interactive login: presents WHOOP's consent screen, verifies
    /// `state`, exchanges the returned code for tokens, and persists them.
    @MainActor
    func login() async throws {
        let (clientID, clientSecret) = try await requireCredentials()
        let state = Self.randomState()
        let authorizeURL = Self.buildAuthorizeURL(clientID: clientID, state: state)

        let runner = AuthSessionRunner()
        let callbackURL = try await runner.run(url: authorizeURL, callbackScheme: OAuthConfig.redirectScheme)

        try Self.verifyState(callbackURL, expected: state)
        guard let code = Self.extractQueryItem(callbackURL, name: "code") else {
            throw AuthError.missingCode(callbackURL)
        }

        try await exchangeCodeForTokens(code: code, clientID: clientID, clientSecret: clientSecret)
    }

    /// Refreshes only if the current access token is expired (or within its 60s
    /// safety margin). Safe to call before every API request — it's a no-op most
    /// of the time.
    func refreshIfNeeded() async throws {
        guard let tokens = try TokenStore.loadTokens() else { throw AuthError.notAuthenticated }
        guard tokens.isExpired else { return }
        try await refreshOnce()
    }

    /// Forces a refresh regardless of the stored expiry — used by `WhoopClient`
    /// after an unexpected 401, in case the token was revoked or the local expiry
    /// estimate drifted from WHOOP's actual clock.
    func forceRefresh() async throws {
        try await refreshOnce()
    }

    /// The single refresh allowed to be in flight. Everything that refreshes goes
    /// through here, so overlapping callers await one request rather than each
    /// spending the same rotating token.
    ///
    /// Storing the task and awaiting it are both reached without an intervening
    /// `await`, so no second caller can slip between them and start its own.
    private func refreshOnce() async throws {
        if let inFlight = refreshInFlight {
            try await inFlight.value
            return
        }

        let task = Task { try await performRefresh() }
        refreshInFlight = task
        defer { refreshInFlight = nil }
        try await task.value
    }

    /// Reads the tokens itself rather than taking them from the caller: by the time
    /// this runs, a refresh that finished moments ago may already have replaced them.
    private func performRefresh() async throws {
        guard let tokens = try TokenStore.loadTokens() else { throw AuthError.notAuthenticated }
        let (clientID, clientSecret) = try requireCredentialsSync()
        try await refresh(refreshToken: tokens.refreshToken, clientID: clientID, clientSecret: clientSecret)
    }

    func validAccessToken() async throws -> String {
        try await refreshIfNeeded()
        guard let tokens = try TokenStore.loadTokens() else { throw AuthError.notAuthenticated }
        return tokens.accessToken
    }

    func signOut() throws {
        try TokenStore.clearTokens()
    }

    // MARK: - Token exchange

    private func exchangeCodeForTokens(code: String, clientID: String, clientSecret: String) async throws {
        let params: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": OAuthConfig.redirectURI,
            "client_id": clientID,
            "client_secret": clientSecret,
        ]
        let tokens = try await postTokenRequest(params)
        try TokenStore.saveTokens(tokens)
    }

    private func refresh(refreshToken: String, clientID: String, clientSecret: String) async throws {
        let params: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
            "client_secret": clientSecret,
        ]
        // WHOOP rotates the refresh token on every use: the response's
        // refresh_token replaces the one we just sent, and the one we sent is now
        // dead. saveTokens writes both as one atomic Keychain item.
        let tokens = try await postTokenRequest(params)
        try TokenStore.saveTokens(tokens)
    }

    private func postTokenRequest(_ params: [String: String]) async throws -> TokenSet {
        var request = URLRequest(url: OAuthConfig.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode(params).data(using: .utf8)

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AuthError.tokenExchangeFailed(status: -1, body: "no response") }
        guard (200..<300).contains(http.statusCode) else {
            throw AuthError.tokenExchangeFailed(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }

        struct TokenResponse: Decodable {
            let accessToken: String
            let refreshToken: String
            let expiresIn: Int
            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
                case refreshToken = "refresh_token"
                case expiresIn = "expires_in"
            }
        }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        return TokenSet(
            accessToken: decoded.accessToken,
            refreshToken: decoded.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(decoded.expiresIn))
        )
    }

    // MARK: - Credentials

    private func requireCredentials() async throws -> (String, String) {
        try requireCredentialsSync()
    }

    private func requireCredentialsSync() throws -> (String, String) {
        guard let creds = try TokenStore.loadClientCredentials() else {
            throw AuthError.missingCredentials
        }
        return creds
    }

    // MARK: - Authorize URL + callback parsing

    private static func buildAuthorizeURL(clientID: String, state: String) -> URL {
        var components = URLComponents(url: OAuthConfig.authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: OAuthConfig.redirectURI),
            URLQueryItem(name: "scope", value: OAuthConfig.scopeString),
            URLQueryItem(name: "state", value: state),
        ]
        return components.url!
    }

    private static func randomState() -> String {
        // 16 random bytes, hex-encoded — well above the entropy needed to make
        // guessing infeasible within an OAuth flow's short lifetime.
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func verifyState(_ url: URL, expected: String) throws {
        guard extractQueryItem(url, name: "state") == expected else {
            throw AuthError.stateMismatch
        }
    }

    private static func extractQueryItem(_ url: URL, name: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == name }?.value
    }

    private static func formEncode(_ params: [String: String]) -> String {
        params.map { key, value in
            let allowed = CharacterSet.urlQueryAllowed.subtracting(.init(charactersIn: "+&="))
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(encodedKey)=\(encodedValue)"
        }.joined(separator: "&")
    }
}

/// Presents `ASWebAuthenticationSession` and bridges its callback-based API to
/// async/await. Must run on the main actor — it touches UIKit window scenes and
/// starting the session is itself a UI action.
@MainActor
private final class AuthSessionRunner: NSObject, ASWebAuthenticationPresentationContextProviding {
    // ASWebAuthenticationSession does not retain itself; without this the session
    // (and its continuation) would be deallocated the instant `run` returns,
    // before the user ever sees the login screen.
    private var activeSession: ASWebAuthenticationSession?

    func run(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callbackURL, error in
                if let error {
                    // Closing the sign-in sheet is a choice, not a failure.
                    let canceled = (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
                    continuation.resume(throwing: canceled ? CancellationError() : error)
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: WhoopAuth.AuthError.presentationFailed)
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = self
            // Sharing WHOOP's existing web session (if any) means a user who's
            // already logged in to whoop.com in Safari doesn't have to re-enter a
            // password here. Fine for a single-user personal app.
            session.prefersEphemeralWebBrowserSession = false
            activeSession = session
            if !session.start() {
                continuation.resume(throwing: WhoopAuth.AuthError.presentationFailed)
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if canImport(UIKit)
        let anchor = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        return anchor ?? ASPresentationAnchor()
        #else
        return ASPresentationAnchor()
        #endif
    }
}
