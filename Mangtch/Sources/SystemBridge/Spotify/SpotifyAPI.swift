import Foundation

/// Thin REST client for the only two Spotify endpoints we need:
/// liked-status check and liked-toggle. Auth is delegated to SpotifyAuth,
/// which handles token refresh transparently.
@MainActor
final class SpotifyAPI {
    static let shared = SpotifyAPI()

    /// Cache `isLiked` results keyed by track ID for 60 s. Track changes
    /// fire on every poll (every 2 s in MediaBridge), and `/me/tracks/contains`
    /// is rate-limited per app, so this avoids hammering it.
    private struct CacheEntry { let liked: Bool; let storedAt: Date }
    private var cache: [String: CacheEntry] = [:]
    private let cacheTTL: TimeInterval = 60

    private init() {}

    // MARK: - Public API

    /// Returns true if the track is in the user's Liked Songs.
    /// Returns false on any error (network, auth, rate limit) so the UI
    /// shows an empty heart rather than getting stuck.
    func isLiked(trackID: String) async -> Bool {
        if let entry = cache[trackID], Date().timeIntervalSince(entry.storedAt) < cacheTTL {
            return entry.liked
        }

        guard let token = await SpotifyAuth.shared.currentAccessToken() else { return false }

        // The legacy `/me/tracks/contains` endpoint was deprecated in 2025 and
        // now returns 403; Spotify replaced it with the unified
        // `/me/library/contains` endpoint that takes Spotify URIs and works for
        // tracks, albums, and other library items in one call.
        var components = URLComponents(string: "https://api.spotify.com/v1/me/library/contains")!
        components.queryItems = [URLQueryItem(name: "uris", value: "spotify:track:\(trackID)")]
        guard let url = components.url else { return false }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let array = try? JSONDecoder().decode([Bool].self, from: data),
                  let first = array.first
            else { return false }
            cache[trackID] = CacheEntry(liked: first, storedAt: Date())
            return first
        } catch {
            return false
        }
    }

    /// Saves or removes the track from Liked Songs.
    /// Returns true on 2xx, false otherwise so callers can roll back optimistic UI.
    func setLiked(trackID: String, liked: Bool) async -> Bool {
        guard let token = await SpotifyAuth.shared.currentAccessToken() else { return false }

        // The legacy `/me/tracks` endpoint was deprecated in 2025 (returns 403
        // with a misleading "Forbidden" body). The replacement is the unified
        // `/me/library` endpoint, which takes Spotify URIs and works for
        // tracks, albums, etc. in a single call.
        var components = URLComponents(string: "https://api.spotify.com/v1/me/library")!
        components.queryItems = [URLQueryItem(name: "uris", value: "spotify:track:\(trackID)")]
        guard let url = components.url else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = liked ? "PUT" : "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return false
            }
            // Update cache so subsequent reads reflect the new state immediately.
            cache[trackID] = CacheEntry(liked: liked, storedAt: Date())
            return true
        } catch {
            return false
        }
    }

    /// Drop the cache (used when signing out so a future re-auth doesn't
    /// see stale results).
    func clearCache() {
        cache.removeAll()
    }
}

/// Extract the bare track ID ("3n3Ppam7vgaVa1iaRUc9Lp") from any of the forms
/// the Spotify AppleScript dictionary returns: `spotify:track:ID`,
/// `https://open.spotify.com/track/ID?si=…`, or already-bare ID.
enum SpotifyTrackID {
    static func extract(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // spotify:track:ID
        if trimmed.hasPrefix("spotify:track:") {
            return String(trimmed.dropFirst("spotify:track:".count))
        }
        // https://open.spotify.com/track/ID[?…]
        if let url = URL(string: trimmed), url.host?.contains("spotify.com") == true {
            let parts = url.pathComponents
            if let idx = parts.firstIndex(of: "track"), idx + 1 < parts.count {
                return parts[idx + 1]
            }
        }
        // Looks like a bare ID (22 base62 chars).
        if trimmed.count == 22, trimmed.allSatisfy({ $0.isLetter || $0.isNumber }) {
            return trimmed
        }
        return nil
    }
}
