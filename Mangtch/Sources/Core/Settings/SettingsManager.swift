import Foundation
import SwiftUI
import Combine
import ServiceManagement

@Observable
@MainActor
final class SettingsManager {
    static let shared = SettingsManager()

    // MARK: - Settings Keys

    private enum Keys {
        static let launchAtLogin = "launchAtLogin"
        static let animationsEnabled = "animationsEnabled"
        static let enableMusicPlayer = "enableMusicPlayer"
        static let enableFileShelf = "enableFileShelf"
        static let fileShelfMaxItems = "fileShelfMaxItems"
        static let fileShelfExpirationHours = "fileShelfExpirationHours"
        static let hoverSensitivity = "hoverSensitivity"
        static let panelWidthMultiplier = "panelWidthMultiplier"
        static let showInMenuBar = "showInMenuBar"
        static let automaticallyCheckForUpdates = "automaticallyCheckForUpdates"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let hideInFullscreen = "hideInFullscreen"
        static let spotifyClientID = "spotifyClientID"
        static let lastExpandedWidgetID = "lastExpandedWidgetID"
    }

    // MARK: - Properties

    private let defaults = UserDefaults.standard

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: Keys.launchAtLogin) }
        set {
            defaults.set(newValue, forKey: Keys.launchAtLogin)
            updateLoginItem(enabled: newValue)
        }
    }

    var animationsEnabled: Bool {
        get { defaults.bool(forKey: Keys.animationsEnabled) }
        set { defaults.set(newValue, forKey: Keys.animationsEnabled) }
    }

    var enableMusicPlayer: Bool {
        get { defaults.bool(forKey: Keys.enableMusicPlayer) }
        set { defaults.set(newValue, forKey: Keys.enableMusicPlayer) }
    }

    var enableFileShelf: Bool {
        get { defaults.bool(forKey: Keys.enableFileShelf) }
        set { defaults.set(newValue, forKey: Keys.enableFileShelf) }
    }

    var fileShelfMaxItems: Int {
        get { defaults.integer(forKey: Keys.fileShelfMaxItems) }
        set { defaults.set(newValue, forKey: Keys.fileShelfMaxItems) }
    }

    var fileShelfExpirationHours: Int {
        get { defaults.integer(forKey: Keys.fileShelfExpirationHours) }
        set { defaults.set(newValue, forKey: Keys.fileShelfExpirationHours) }
    }

    var hoverSensitivity: Double {
        get { defaults.double(forKey: Keys.hoverSensitivity) }
        set { defaults.set(newValue, forKey: Keys.hoverSensitivity) }
    }

    var panelWidthMultiplier: Double {
        get { defaults.double(forKey: Keys.panelWidthMultiplier) }
        set { defaults.set(newValue, forKey: Keys.panelWidthMultiplier) }
    }

    var showInMenuBar: Bool {
        get { defaults.bool(forKey: Keys.showInMenuBar) }
        set { defaults.set(newValue, forKey: Keys.showInMenuBar) }
    }

    var automaticallyCheckForUpdates: Bool {
        get { defaults.bool(forKey: Keys.automaticallyCheckForUpdates) }
        set {
            defaults.set(newValue, forKey: Keys.automaticallyCheckForUpdates)
            UpdateManager.shared.updater?.automaticallyChecksForUpdates = newValue
        }
    }

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Keys.hasCompletedOnboarding) }
        set { defaults.set(newValue, forKey: Keys.hasCompletedOnboarding) }
    }

    var hideInFullscreen: Bool {
        get { defaults.bool(forKey: Keys.hideInFullscreen) }
        set { defaults.set(newValue, forKey: Keys.hideInFullscreen) }
    }

    /// Spotify Web API Client ID (PKCE flow — no secret).
    /// User pastes this from https://developer.spotify.com/dashboard.
    var spotifyClientID: String {
        get { defaults.string(forKey: Keys.spotifyClientID) ?? "" }
        set { defaults.set(newValue, forKey: Keys.spotifyClientID) }
    }

    /// ID of the widget shown in the expanded panel; persisted across sessions.
    /// nil on first run — the switcher falls back to the music player.
    var lastExpandedWidgetID: String? {
        get { defaults.string(forKey: Keys.lastExpandedWidgetID) }
        set { defaults.set(newValue, forKey: Keys.lastExpandedWidgetID) }
    }

    // MARK: - Initialization

    private init() {
        registerDefaults()
    }

    private func registerDefaults() {
        defaults.register(defaults: [
            Keys.launchAtLogin: false,
            Keys.animationsEnabled: true,
            Keys.enableMusicPlayer: true,
            Keys.enableFileShelf: true,
            Keys.fileShelfMaxItems: 3,
            Keys.fileShelfExpirationHours: 24,
            Keys.hoverSensitivity: 0.5,
            Keys.panelWidthMultiplier: 1.0,
            Keys.showInMenuBar: true,
            Keys.automaticallyCheckForUpdates: true,
            Keys.hasCompletedOnboarding: false,
            Keys.hideInFullscreen: true,
        ])
    }

    // MARK: - Launch at Login

    private func updateLoginItem(enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("[SettingsManager] Failed to update login item: \(error)")
            }
        }
    }

    // MARK: - Reset

    func resetToDefaults() {
        let domain = Bundle.main.bundleIdentifier ?? "com.yojeong.mangtch"
        defaults.removePersistentDomain(forName: domain)
        registerDefaults()
    }
}
