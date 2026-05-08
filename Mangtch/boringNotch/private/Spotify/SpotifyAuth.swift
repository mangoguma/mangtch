import Foundation
import AppKit
import CryptoKit
import Combine
import Defaults

/// Handles the Spotify OAuth Authorization Code flow with PKCE.
/// Native macOS apps can't safely embed a client_secret, so PKCE is mandatory.
/// Reference: https://developer.spotify.com/documentation/web-api/tutorials/code-pkce-flow
@MainActor
final class SpotifyAuth: ObservableObject {
    static let shared = SpotifyAuth()

    // MARK: - Published

    @Published private(set) var isAuthorized: Bool = false
    @Published private(set) var displayName: String?
    @Published private(set) var lastError: String?

    // MARK: - Private

    /// PKCE verifier we generated for the in-flight auth request. Kept in
    /// memory only — it's worthless once the code exchange completes.
    private var pendingVerifier: String?
    private var pendingState: String?

    private static let scope = "user-library-read user-library-modify"
    private static let redirectURI = "mangtch://spotify-callback"
    private static let authorizeBase = "https://accounts.spotify.com/authorize"
    private static let tokenBase = "https://accounts.spotify.com/api/token"

    // MARK: - Init

    private init() {
        if SpotifyTokenStore.load() != nil {
            isAuthorized = true
            Task { await fetchProfile() }
        }
    }

    // MARK: - Public API

    func startAuthFlow(clientID: String) {
        guard !clientID.isEmpty else {
            lastError = "Client ID is empty"
            return
        }

        let verifier = Self.generateCodeVerifier()
        let challenge = Self.codeChallenge(for: verifier)
        let state = UUID().uuidString
        pendingVerifier = verifier
        pendingState = state

        var components = URLComponents(string: Self.authorizeBase)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "scope", value: Self.scope),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "state", value: state),
            // Force the consent screen on every sign-in. Without this, Spotify
            // silently re-issues a token using whatever scopes the user
            // previously consented to — if scopes change in the app, the user
            // never sees the new consent prompt and the new scope is missing.
            URLQueryItem(name: "show_dialog", value: "true"),
        ]

        guard let url = components.url else {
            lastError = "Failed to build authorize URL"
            return
        }

        NSWorkspace.shared.open(url)
        lastError = nil
    }

    func handleCallback(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              let state = components.queryItems?.first(where: { $0.name == "state" })?.value
        else {
            if let err = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "error" })?.value {
                lastError = "Spotify error: \(err)"
            } else {
                lastError = "Invalid callback URL"
            }
            return
        }

        guard state == pendingState else {
            lastError = "State mismatch — possible CSRF, ignoring callback"
            return
        }

        guard let verifier = pendingVerifier else {
            lastError = "No verifier in memory — start the flow again"
            return
        }

        let clientID = Defaults[.spotifyClientID]
        guard !clientID.isEmpty else {
            lastError = "Client ID missing in Settings"
            return
        }

        Task { await exchangeCode(code, verifier: verifier, clientID: clientID) }
        pendingVerifier = nil
        pendingState = nil
    }

    func disconnect() {
        SpotifyTokenStore.delete()
        isAuthorized = false
        displayName = nil
        lastError = nil
    }

    /// Returns a fresh access_token, refreshing if necessary.
    /// Called by SpotifyAPI before every request.
    func currentAccessToken() async -> String? {
        guard let tokens = SpotifyTokenStore.load() else { return nil }
        if !tokens.isExpired { return tokens.accessToken }

        let clientID = await MainActor.run { Defaults[.spotifyClientID] }
        guard !clientID.isEmpty else { return nil }
        return await refreshAccessToken(refreshToken: tokens.refreshToken, clientID: clientID)
    }

    // MARK: - Private: Token Exchange

    private func exchangeCode(_ code: String, verifier: String, clientID: String) async {
        var request = URLRequest(url: URL(string: Self.tokenBase)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Self.redirectURI,
            "client_id": clientID,
            "code_verifier": verifier,
        ]).data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let body = String(data: data, encoding: .utf8) ?? ""
                lastError = "Token exchange failed: \(body)"
                return
            }
            let resp = try JSONDecoder().decode(TokenResponse.self, from: data)
            guard let refresh = resp.refresh_token else {
                lastError = "No refresh_token in response"
                return
            }
            let tokens = SpotifyTokens(
                accessToken: resp.access_token,
                refreshToken: refresh,
                expiresAt: Date().addingTimeInterval(TimeInterval(resp.expires_in))
            )
            try SpotifyTokenStore.save(tokens)
            isAuthorized = true
            lastError = nil
            await fetchProfile()
        } catch {
            lastError = "Token exchange error: \(error.localizedDescription)"
        }
    }

    private func refreshAccessToken(refreshToken: String, clientID: String) async -> String? {
        var request = URLRequest(url: URL(string: Self.tokenBase)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
        ]).data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                if let http = response as? HTTPURLResponse, http.statusCode == 400 {
                    SpotifyTokenStore.delete()
                    await MainActor.run {
                        self.isAuthorized = false
                        self.displayName = nil
                        self.lastError = "Session expired — please sign in again"
                    }
                }
                return nil
            }
            let resp = try JSONDecoder().decode(TokenResponse.self, from: data)
            let newRefresh = resp.refresh_token ?? refreshToken
            let tokens = SpotifyTokens(
                accessToken: resp.access_token,
                refreshToken: newRefresh,
                expiresAt: Date().addingTimeInterval(TimeInterval(resp.expires_in))
            )
            try? SpotifyTokenStore.save(tokens)
            return resp.access_token
        } catch {
            return nil
        }
    }

    // MARK: - Private: Profile

    private func fetchProfile() async {
        guard let token = await currentAccessToken() else { return }
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            struct Me: Decodable { let display_name: String? }
            let me = try JSONDecoder().decode(Me.self, from: data)
            displayName = me.display_name
        } catch {
            // Non-fatal — UI just falls back to "Connected"
        }
    }

    // MARK: - Private: PKCE Helpers

    private static func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 48)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded()
    }

    private static func codeChallenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64URLEncoded()
    }

    private static func formEncode(_ params: [String: String]) -> String {
        params.map { key, value in
            let v = value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
            return "\(key)=\(v)"
        }.joined(separator: "&")
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let token_type: String
        let expires_in: Int
        let refresh_token: String?
        let scope: String?
    }
}

private extension Data {
    /// Base64-URL encoding (no padding) per RFC 4648 §5.
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
