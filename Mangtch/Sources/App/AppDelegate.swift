import AppKit
import SwiftUI
import Combine
import Defaults
import Sparkle

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[Mangtch] applicationDidFinishLaunching started")

        // Set as accessory app (no dock icon)
        NSApplication.shared.setActivationPolicy(.accessory)

        // Ensure app is activated and connected to WindowServer
        NSApplication.shared.activate(ignoringOtherApps: true)

        NSLog("[Mangtch] NSApplication activated")

        // Initialize settings
        _ = SettingsManager.shared

        // Setup menu bar
        Task { @MainActor in
            MenuBarManager.shared.setup()
        }

        // Initialize system bridges
        NSLog("[AppDelegate] About to call MusicManager.shared.startMonitoring()")
        MusicManager.shared.startMonitoring()
        NSLog("[AppDelegate] MusicManager.shared.startMonitoring() completed")
        SystemInfoBridge.shared.startMonitoring()

        // Register all widgets
        Task { @MainActor in
            WidgetRegistry.shared.registerDefaults()
            WidgetRegistry.shared.activateAll()
        }

        // Setup gesture handling
        Task { @MainActor in
            GestureHandler.shared.setup()
        }

        // Drag detector (auto-surface FileShelf when a file is dragged
        // toward the notch). Off-by-default behavior is gated by Defaults.
        Task { @MainActor in
            if Defaults[.expandedDragDetection] {
                DragDetector.shared.start()
            }
        }

        // Setup global shortcuts
        Task { @MainActor in
            ShortcutManager.shared.setup()
        }

        // Register the mangtch:// URL handler so Spotify OAuth callbacks
        // route to SpotifyAuth (LSUIElement apps don't get
        // application(_:open:) for free).
        Task { @MainActor in
            SpotifyURLHandler.shared.register()
        }

        // Start Sparkle auto-updater
        UpdateManager.shared.start()

        // Show onboarding if needed (first launch or missing permissions)
        if OnboardingWindow.shared.shouldShow {
            OnboardingWindow.shared.show()
        }

        // Setup notch window(s) with delay to ensure WindowServer connection.
        // Manager handles screen-change reconciliation internally.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            Task { @MainActor in
                NotchWindowManager.shared.sync()
            }
        }

        print("[Mangtch] Launch complete")
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in
            WidgetRegistry.shared.deactivateAll()
            MusicManager.shared.stopMonitoring()
            SystemInfoBridge.shared.stopMonitoring()
            GestureHandler.shared.teardown()
            DragDetector.shared.stop()
            ShortcutManager.shared.teardown()
            MenuBarManager.shared.teardown()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Don't quit when settings window closes
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // When user double-clicks the app while already running, show settings
        MenuBarManager.shared.openSettings()
        return false
    }
}
