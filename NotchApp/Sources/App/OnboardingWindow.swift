import AppKit
import SwiftUI

/// Manages the onboarding window lifecycle.
@MainActor
final class OnboardingWindow {
    static let shared = OnboardingWindow()

    private var window: NSWindow?

    private init() {}

    /// Shows the onboarding window. If already visible, brings it to front.
    func show() {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let onboardingView = OnboardingView(onComplete: { [weak self] in
            self?.close()
        })

        let hostingController = NSHostingController(rootView: onboardingView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Welcome to Mangtch"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 520, height: 440))
        window.center()
        window.level = .floating
        window.isMovableByWindowBackground = true

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Closes the onboarding window.
    func close() {
        window?.close()
        window = nil
    }

    /// Whether onboarding should be shown (first launch or missing permissions).
    var shouldShow: Bool {
        !SettingsManager.shared.hasCompletedOnboarding || !AXIsProcessTrusted()
    }
}
