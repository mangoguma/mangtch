import AppKit
import Defaults

/// Decides which `NSScreen` the notch panel attaches to, based on the
/// user's `notchScreen` preference. Default (empty pref) is the built-in
/// display — `NSScreen.screens[0]` — which preserves the original
/// behaviour for users who never touch the setting. When the chosen
/// screen has been disconnected, we fall back to the built-in display
/// instead of orphaning the panel.
enum NotchScreenResolver {
    static func activeScreen() -> NSScreen? {
        // Read straight from Defaults so callers off the main actor (the
        // global mouse/drag observers) can resolve without an actor hop.
        let pref = Defaults[.notchScreen]
        guard !pref.isEmpty else {
            return NSScreen.screens.first
        }
        return NSScreen.screens.first(where: { $0.localizedName == pref })
            ?? NSScreen.screens.first
    }
}
