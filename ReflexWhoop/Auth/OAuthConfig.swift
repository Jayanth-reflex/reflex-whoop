import Foundation

/// Static WHOOP OAuth2 endpoints and scope list. Per-app values (client id/secret)
/// are supplied by the user at runtime via the Setup screen and live only in
/// Keychain — see `TokenStore`. Nothing here is a secret.
enum OAuthConfig {
    static let authorizeURL = URL(string: "https://api.prod.whoop.com/oauth/oauth2/auth")!
    static let tokenURL = URL(string: "https://api.prod.whoop.com/oauth/oauth2/token")!

    /// Must exactly match a redirect URL registered on the WHOOP Developer Dashboard.
    static let redirectURI = "reflexwhoop://oauth/callback"
    static let redirectScheme = "reflexwhoop"

    /// `offline` is what makes WHOOP issue a refresh token — without it every access
    /// token expiry would force a full interactive re-login. The WHOOP Developer
    /// Dashboard's "Scopes" section (as of app creation) only lists the six
    /// data-access scopes below with no `offline` toggle; `offline` appears to be a
    /// protocol-level modifier requested in the authorize URL rather than a
    /// per-app-registered scope. Included here regardless — if WHOOP silently drops
    /// it, `WhoopAuth` will get no refresh token back and that failure mode is
    /// exactly what live-testing this in Phase 2 is for.
    static let scopes = [
        "read:profile",
        "read:body_measurement",
        "read:cycles",
        "read:recovery",
        "read:sleep",
        "read:workout",
        "offline",
    ]

    static var scopeString: String { scopes.joined(separator: " ") }
}
