import AppKit
import SwiftUI

@MainActor
final class MenuBarManager {
    static let shared = MenuBarManager()

    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?

    private init() {}

    func setup() {
        guard SettingsManager.shared.showInMenuBar else { return }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "Mangtch")
            button.image?.size = NSSize(width: 18, height: 18)
        }

        setupMenu()
    }

    func teardown() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    private func setupMenu() {
        let menu = NSMenu()

        // App name
        let titleItem = NSMenuItem(title: "Mangtch", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        menu.addItem(NSMenuItem.separator())

        // Check for Updates
        let updateItem = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        updateItem.target = self
        menu.addItem(updateItem)

        menu.addItem(NSMenuItem.separator())

        // Settings
        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        // Setup Permissions
        let permissionsItem = NSMenuItem(
            title: "Setup Permissions…",
            action: #selector(showOnboarding),
            keyEquivalent: ""
        )
        permissionsItem.target = self
        menu.addItem(permissionsItem)

        menu.addItem(NSMenuItem.separator())

        // About
        let aboutItem = NSMenuItem(
            title: "About Mangtch",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit Mangtch",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc private func checkForUpdates() {
        UpdateManager.shared.checkForUpdates()
    }

    @objc func openSettings() {
        // macOS 14 deprecated `NSApp.sendAction(#selector(showSettingsWindow:))`
        // for SwiftUI's `Settings` scene — the runtime now logs
        //   "Please use SettingsLink for opening the Settings scene."
        // and silently no-ops, never creating the window. SettingsLink only
        // works inside a SwiftUI view tree, which an NSMenuItem isn't.
        // So we host the SwiftUI SettingsView in a plain NSWindow and manage
        // its lifecycle ourselves. This sidesteps the regression entirely.
        NSApp.activate(ignoringOtherApps: true)

        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            let window = NSWindow(contentViewController: hosting)
            window.title = "Mangtch Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setContentSize(NSSize(width: 580, height: 400))
            window.center()
            window.isReleasedWhenClosed = false  // reuse instance on subsequent opens
            settingsWindow = window
        }

        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.orderFrontRegardless()
    }

    @objc private func showOnboarding() {
        NSApp.activate()
        OnboardingWindow.shared.show()
    }

    @objc private func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
