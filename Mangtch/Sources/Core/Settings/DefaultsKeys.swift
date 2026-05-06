import Defaults
import Foundation

// Centralized typed keys for sindresorhus/Defaults.
// Key names match SettingsManager's previous UserDefaults strings so
// existing values survive an update without migration.
extension Defaults.Keys {
    static let launchAtLogin = Key<Bool>("launchAtLogin", default: false)
    static let animationsEnabled = Key<Bool>("animationsEnabled", default: true)
    static let enableMusicPlayer = Key<Bool>("enableMusicPlayer", default: true)
    static let enableFileShelf = Key<Bool>("enableFileShelf", default: true)
    static let fileShelfMaxItems = Key<Int>("fileShelfMaxItems", default: 3)
    static let fileShelfExpirationHours = Key<Int>("fileShelfExpirationHours", default: 24)
    static let panelWidthMultiplier = Key<Double>("panelWidthMultiplier", default: 1.0)
    static let showInMenuBar = Key<Bool>("showInMenuBar", default: true)
    static let automaticallyCheckForUpdates = Key<Bool>("automaticallyCheckForUpdates", default: true)
    static let hasCompletedOnboarding = Key<Bool>("hasCompletedOnboarding", default: false)
    static let hideInFullscreen = Key<Bool>("hideInFullscreen", default: true)
    static let spotifyClientID = Key<String>("spotifyClientID", default: "")
    static let lastExpandedWidgetID = Key<String?>("lastExpandedWidgetID", default: nil)
    static let kboSelectedGameID = Key<String?>("kboSelectedGameID", default: nil)
    static let kboTickerEnabled = Key<Bool>("kboTickerEnabled", default: true)
    static let kboTextToSpeechEnabled = Key<Bool>("kboTextToSpeechEnabled", default: false)
    static let expandedDragDetection = Key<Bool>("expandedDragDetection", default: true)
    /// When true, dwelling the cursor over the notch cutout opens the panel
    /// (after `minimumHoverDuration`). When false, only pan-down or click
    /// triggers expand. Wing hover (idle → hovering) is unaffected.
    static let openNotchOnHover = Key<Bool>("openNotchOnHover", default: true)
    /// Seconds the cursor must rest over the notch before auto-expand fires.
    static let minimumHoverDuration = Key<Double>("minimumHoverDuration", default: 0.3)
    /// Identifier of the screen the notch panel should attach to. Empty
    /// string (default) means the built-in display (`NSScreen.screens[0]`).
    /// Otherwise the value is `NSScreen.localizedName`.
    static let notchScreen = Key<String>("notchScreen", default: "")
    /// When true, a notch panel is mirrored onto every connected display.
    /// `notchScreen` is ignored while this is on.
    static let showOnAllDisplays = Key<Bool>("showOnAllDisplays", default: false)
    /// Last selected timer mode (countdown vs stopwatch).
    static let timerMode = Key<String>("timerMode", default: "Timer")
    /// Show zone overlays and hover timer on the notch panel for debugging.
    static let debugOverlay = Key<Bool>("debugOverlay", default: false)
}
