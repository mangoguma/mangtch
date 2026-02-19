import AppKit
import SwiftUI
import Combine
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
        NSLog("[AppDelegate] About to call MediaBridge.shared.startMonitoring()")
        MediaBridge.shared.startMonitoring()
        NSLog("[AppDelegate] MediaBridge.shared.startMonitoring() completed")
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

        // Setup global shortcuts
        Task { @MainActor in
            ShortcutManager.shared.setup()
        }

        // Start Sparkle auto-updater
        UpdateManager.shared.start()

        // Show onboarding if needed (first launch or missing permissions)
        if OnboardingWindow.shared.shouldShow {
            OnboardingWindow.shared.show()
        }

        // Setup notch window with delay to ensure WindowServer connection
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            Task { @MainActor in
                NotchWindow.shared.setup()
            }
        }

        // Observe screen changes for repositioning
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    NotchWindow.shared.reposition()
                }
            }
            .store(in: &cancellables)

        print("[Mangtch] Launch complete")
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in
            WidgetRegistry.shared.deactivateAll()
            MediaBridge.shared.stopMonitoring()
            SystemInfoBridge.shared.stopMonitoring()
            GestureHandler.shared.teardown()
            ShortcutManager.shared.teardown()
            MenuBarManager.shared.teardown()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Don't quit when settings window closes
        return false
    }
}
