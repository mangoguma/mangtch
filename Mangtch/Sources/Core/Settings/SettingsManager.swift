import Foundation
import SwiftUI
import Combine
import Defaults
import ServiceManagement

@Observable
@MainActor
final class SettingsManager {
    static let shared = SettingsManager()

    var launchAtLogin: Bool {
        get { Defaults[.launchAtLogin] }
        set {
            Defaults[.launchAtLogin] = newValue
            updateLoginItem(enabled: newValue)
        }
    }

    var animationsEnabled: Bool {
        get { Defaults[.animationsEnabled] }
        set { Defaults[.animationsEnabled] = newValue }
    }

    var enableMusicPlayer: Bool {
        get { Defaults[.enableMusicPlayer] }
        set { Defaults[.enableMusicPlayer] = newValue }
    }

    var enableFileShelf: Bool {
        get { Defaults[.enableFileShelf] }
        set { Defaults[.enableFileShelf] = newValue }
    }

    var fileShelfMaxItems: Int {
        get { Defaults[.fileShelfMaxItems] }
        set { Defaults[.fileShelfMaxItems] = newValue }
    }

    var fileShelfExpirationHours: Int {
        get { Defaults[.fileShelfExpirationHours] }
        set { Defaults[.fileShelfExpirationHours] = newValue }
    }

    var hoverSensitivity: Double {
        get { Defaults[.hoverSensitivity] }
        set { Defaults[.hoverSensitivity] = newValue }
    }

    var panelWidthMultiplier: Double {
        get { Defaults[.panelWidthMultiplier] }
        set { Defaults[.panelWidthMultiplier] = newValue }
    }

    var showInMenuBar: Bool {
        get { Defaults[.showInMenuBar] }
        set { Defaults[.showInMenuBar] = newValue }
    }

    var automaticallyCheckForUpdates: Bool {
        get { Defaults[.automaticallyCheckForUpdates] }
        set {
            Defaults[.automaticallyCheckForUpdates] = newValue
            UpdateManager.shared.updater?.automaticallyChecksForUpdates = newValue
        }
    }

    var hasCompletedOnboarding: Bool {
        get { Defaults[.hasCompletedOnboarding] }
        set { Defaults[.hasCompletedOnboarding] = newValue }
    }

    var hideInFullscreen: Bool {
        get { Defaults[.hideInFullscreen] }
        set { Defaults[.hideInFullscreen] = newValue }
    }

    /// Localized name of the screen the notch panel attaches to. Empty
    /// string = built-in display (`NSScreen.screens[0]`).
    var notchScreen: String {
        get { Defaults[.notchScreen] }
        set { Defaults[.notchScreen] = newValue }
    }

    var showOnAllDisplays: Bool {
        get { Defaults[.showOnAllDisplays] }
        set { Defaults[.showOnAllDisplays] = newValue }
    }

    /// Spotify Web API Client ID (PKCE flow — no secret).
    /// User pastes this from https://developer.spotify.com/dashboard.
    var spotifyClientID: String {
        get { Defaults[.spotifyClientID] }
        set { Defaults[.spotifyClientID] = newValue }
    }

    /// ID of the widget shown in the expanded panel; persisted across sessions.
    /// nil on first run — the switcher falls back to the music player.
    var lastExpandedWidgetID: String? {
        get { Defaults[.lastExpandedWidgetID] }
        set { Defaults[.lastExpandedWidgetID] = newValue }
    }

    /// Game ID the user pinned to the KBO widget's left-wing compact view.
    /// nil = no pin → wing falls back to music. Stored as the Naver-format
    /// gameId (e.g. "20250501LGHH02025"); validity is the widget's concern.
    var kboSelectedGameID: String? {
        get { Defaults[.kboSelectedGameID] }
        set { Defaults[.kboSelectedGameID] = newValue }
    }

    var kboTickerEnabled: Bool {
        get { Defaults[.kboTickerEnabled] }
        set { Defaults[.kboTickerEnabled] = newValue }
    }

    var kboTextToSpeechEnabled: Bool {
        get { Defaults[.kboTextToSpeechEnabled] }
        set { Defaults[.kboTextToSpeechEnabled] = newValue }
    }

    private init() {}

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

    func resetToDefaults() {
        Defaults.removeAll()
    }
}
