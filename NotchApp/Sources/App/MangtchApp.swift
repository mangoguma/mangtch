import SwiftUI

@main
struct MangtchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Settings window (opened from menu bar)
        Settings {
            SettingsView()
        }
    }
}
