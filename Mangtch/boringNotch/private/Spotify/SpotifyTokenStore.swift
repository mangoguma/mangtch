import Foundation
import Security

/// Persists Spotify OAuth tokens in the macOS Keychain so refresh_token is
/// never written to UserDefaults or disk in plaintext. The whole token bundle
/// is stored as a single JSON-encoded `kSecClassGenericPassword` item.
struct SpotifyTokens: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date

    var isExpired: Bool {
        // 60-second safety margin so we proactively refresh before the token
        // actually expires mid-request.
        Date() > expiresAt.addingTimeInterval(-60)
    }
}

enum SpotifyTokenStore {
    private static let service = "com.yojeong.mangtch.spotify"
    private static let account = "oauth-tokens"

    static func save(_ tokens: SpotifyTokens) throws {
        let data = try JSONEncoder().encode(tokens)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let updateAttrs: [String: Any] = [
            kSecValueData as String: data
        ]

        let status = SecItemUpdate(query as CFDictionary, updateAttrs as CFDictionary)
        if status == errSecSuccess { return }

        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw SpotifyTokenStoreError.keychainError(addStatus)
            }
            return
        }

        throw SpotifyTokenStoreError.keychainError(status)
    }

    static func load() -> SpotifyTokens? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(SpotifyTokens.self, from: data)
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum SpotifyTokenStoreError: Error {
    case keychainError(OSStatus)
}
