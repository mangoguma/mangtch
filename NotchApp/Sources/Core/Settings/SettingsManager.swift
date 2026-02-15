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
        static let enableHUD = "enableHUD"
        static let fileShelfMaxItems = "fileShelfMaxItems"
        static let fileShelfExpirationHours = "fileShelfExpirationHours"
        static let hudAutoHideDelay = "hudAutoHideDelay"
        static let hoverSensitivity = "hoverSensitivity"
        static let panelWidthMultiplier = "panelWidthMultiplier"
        static let showInMenuBar = "showInMenuBar"
        static let suppressSystemHUD = "suppressSystemHUD"
        static let automaticallyCheckForUpdates = "automaticallyCheckForUpdates"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
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

    var enableHUD: Bool {
        get { defaults.bool(forKey: Keys.enableHUD) }
        set { defaults.set(newValue, forKey: Keys.enableHUD) }
    }

    var fileShelfMaxItems: Int {
        get { defaults.integer(forKey: Keys.fileShelfMaxItems) }
        set { defaults.set(newValue, forKey: Keys.fileShelfMaxItems) }
    }

    var fileShelfExpirationHours: Int {
        get { defaults.integer(forKey: Keys.fileShelfExpirationHours) }
        set { defaults.set(newValue, forKey: Keys.fileShelfExpirationHours) }
    }

    var hudAutoHideDelay: Double {
        get { defaults.double(forKey: Keys.hudAutoHideDelay) }
        set { defaults.set(newValue, forKey: Keys.hudAutoHideDelay) }
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

    var suppressSystemHUD: Bool {
        get { defaults.bool(forKey: Keys.suppressSystemHUD) }
        set { defaults.set(newValue, forKey: Keys.suppressSystemHUD) }
    }

    var automaticallyCheckForUpdates: Bool {
        get { defaults.bool(forKey: Keys.automaticallyCheckForUpdates) }
        set {
            defaults.set(newValue, forKey: Keys.automaticallyCheckForUpdates)
            UpdateManager.shared.updater.automaticallyChecksForUpdates = newValue
        }
    }

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Keys.hasCompletedOnboarding) }
        set { defaults.set(newValue, forKey: Keys.hasCompletedOnboarding) }
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
            Keys.enableHUD: true,
            Keys.fileShelfMaxItems: 3,
            Keys.fileShelfExpirationHours: 24,
            Keys.hudAutoHideDelay: 2.0,
            Keys.hoverSensitivity: 0.5,
            Keys.panelWidthMultiplier: 1.0,
            Keys.showInMenuBar: true,
            Keys.suppressSystemHUD: false,
            Keys.automaticallyCheckForUpdates: true,
            Keys.hasCompletedOnboarding: false,
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
