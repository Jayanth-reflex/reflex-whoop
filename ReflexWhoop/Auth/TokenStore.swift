import Foundation

/// Access + refresh token, written as one atomic Keychain item. This matters
/// because WHOOP rotates the refresh token on every use: using a refresh token
/// invalidates both the old access token and the old refresh token, and returns
/// new versions of both. Storing them as three separate Keychain writes would
/// leave a window where a crash mid-write loses the new refresh token while the
/// old one is already dead — unrecoverable without a full re-login. One JSON blob,
/// one `SecItemAdd`, makes that window disappear.
struct TokenSet: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date

    var isExpired: Bool {
        // 60s safety margin — never hand out a token that's about to expire
        // mid-request.
        Date() > expiresAt.addingTimeInterval(-60)
    }
}

enum TokenStore {
    private static let tokensKey = "whoop_tokens"
    private static let clientIDKey = "whoop_client_id"
    private static let clientSecretKey = "whoop_client_secret"

    // MARK: - Tokens

    static func saveTokens(_ tokens: TokenSet) throws {
        let data = try JSONEncoder().encode(tokens)
        try KeychainStore.set(data, forKey: tokensKey)
    }

    static func loadTokens() throws -> TokenSet? {
        guard let data = try KeychainStore.get(forKey: tokensKey) else { return nil }
        return try JSONDecoder().decode(TokenSet.self, from: data)
    }

    static func clearTokens() throws {
        try KeychainStore.delete(forKey: tokensKey)
    }

    // MARK: - App credentials (pasted once in Setup, per the design's "never in source" rule)

    static func saveClientCredentials(clientID: String, clientSecret: String) throws {
        try KeychainStore.set(Data(clientID.utf8), forKey: clientIDKey)
        try KeychainStore.set(Data(clientSecret.utf8), forKey: clientSecretKey)
    }

    static func loadClientCredentials() throws -> (clientID: String, clientSecret: String)? {
        guard
            let idData = try KeychainStore.get(forKey: clientIDKey),
            let secretData = try KeychainStore.get(forKey: clientSecretKey),
            let id = String(data: idData, encoding: .utf8),
            let secret = String(data: secretData, encoding: .utf8)
        else { return nil }
        return (id, secret)
    }

    static func clearAll() throws {
        try KeychainStore.delete(forKey: tokensKey)
        try KeychainStore.delete(forKey: clientIDKey)
        try KeychainStore.delete(forKey: clientSecretKey)
    }
}
