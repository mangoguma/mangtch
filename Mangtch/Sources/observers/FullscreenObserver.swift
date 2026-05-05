import AppKit
import ApplicationServices
import Combine

/// Detects fullscreen state using a combination of:
/// 1. Accessibility API (AXFullScreen) — for macOS native fullscreen
/// 2. CGWindowListCopyWindowInfo — for in-app fullscreen (e.g., YouTube F key)
///
/// Uses debounce on exit to prevent flickering when CGWindowList
/// returns inconsistent results during Space transitions.
@Observable
@MainActor
final class FullscreenObserver {
    // MARK: - State

    private(set) var isFullscreenAppActive: Bool = false

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()
    private var pollTimer: Timer?
    private var consecutiveNonFullscreenCount: Int = 0
    private let requiredExitChecks: Int = 3

    // MARK: - Init

    init() {
        // Silent check — never trigger the system prompt on launch.
        // Permission is requested explicitly from the onboarding flow.
        let trusted = AXIsProcessTrusted()
        NSLog("[FullscreenObserver] AXIsProcessTrusted: \(trusted)\(trusted ? "" : " — fullscreen detection falls back to CGWindowList")")

        setupObservers()
        startPolling()
        // Run an immediate check so callers that read
        // `isFullscreenAppActive` right after init get the real state
        // instead of the default `false`.
        check()
    }

    // MARK: - Observers

    private func setupObservers() {
        let workspace = NSWorkspace.shared

        workspace.notificationCenter
            .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.check()
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(500))
                    self?.check()
                }
            }
            .store(in: &cancellables)

        workspace.notificationCenter
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.check()
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(300))
                    self?.check()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Polling

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.check()
            }
        }
    }

    // MARK: - Combined Detection

    private func check() {
        guard let screen = NotchScreenResolver.activeScreen() else {
            applyState(false)
            return
        }

        let frontApp = NSWorkspace.shared.frontmostApplication
        let myPID = ProcessInfo.processInfo.processIdentifier

        // Skip if our own app is frontmost
        if frontApp?.processIdentifier == myPID {
            // Don't change state when we are frontmost — keep previous state
            return
        }

        // Method 1: AXFullScreen on focused window
        let axResult = checkAXFullscreen(app: frontApp)

        // Method 2: CGWindowList for screen-covering window
        let cgResult = checkCGWindowFullscreen(screen: screen, excludePID: myPID)

        applyState(axResult || cgResult)
    }

    /// Debounced state application:
    /// - Enter fullscreen: immediate
    /// - Exit fullscreen: requires N consecutive non-fullscreen checks
    private func applyState(_ detected: Bool) {
        if detected {
            consecutiveNonFullscreenCount = 0
            if !isFullscreenAppActive {
                NSLog("[FullscreenObserver] === ENTERING FULLSCREEN ===")
                isFullscreenAppActive = true
            }
        } else {
            if isFullscreenAppActive {
                consecutiveNonFullscreenCount += 1
                if consecutiveNonFullscreenCount >= requiredExitChecks {
                    NSLog("[FullscreenObserver] === EXITING FULLSCREEN (after \(consecutiveNonFullscreenCount) checks) ===")
                    isFullscreenAppActive = false
                    consecutiveNonFullscreenCount = 0
                }
            } else {
                consecutiveNonFullscreenCount = 0
            }
        }
    }

    // MARK: - AX Detection

    private func checkAXFullscreen(app: NSRunningApplication?) -> Bool {
        guard let app = app else { return false }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        var focusedWindow: AnyObject?
        let windowResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        )

        guard windowResult == .success, let window = focusedWindow else {
            return false
        }

        var fullscreenValue: AnyObject?
        let fsResult = AXUIElementCopyAttributeValue(
            window as! AXUIElement,
            "AXFullScreen" as CFString,
            &fullscreenValue
        )

        if fsResult == .success {
            return (fullscreenValue as? Bool) == true
        }
        return false
    }

    // MARK: - CGWindow Detection

    /// Check for a window that covers the entire primary display.
    /// Primary display origin is (0,0) in Quartz coordinates.
    private func checkCGWindowFullscreen(screen: NSScreen, excludePID: pid_t) -> Bool {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return false
        }

        let screenWidth = screen.frame.width
        let screenHeight = screen.frame.height

        // If the system menu bar (Window Server, level 24) is visible on
        // screen, we're in a normal Space — any screen-covering window is
        // just maximized, not fullscreen. Only flag fullscreen when the
        // menu bar is absent (i.e. the current Space IS a fullscreen space).
        let menuBarVisible = windowList.contains { info in
            let layer = info[kCGWindowLayer as String] as? Int ?? -1
            let owner = info[kCGWindowOwnerName as String] as? String ?? ""
            return layer == 24 && owner == "Window Server"
        }
        if menuBarVisible {
            // Normal Space with menu bar → no true fullscreen here.
            // Fall through only for the traditional Y=0 check which catches
            // in-app fullscreen (e.g. YouTube F-key) that covers the menu bar.
        }

        for windowInfo in windowList {
            guard let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat],
                  let windowLayer = windowInfo[kCGWindowLayer as String] as? Int,
                  let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? pid_t else {
                continue
            }

            guard windowLayer == 0 else { continue }
            guard ownerPID != excludePID else { continue }

            if let ownerName = windowInfo[kCGWindowOwnerName as String] as? String {
                let systemApps = ["Finder", "SystemUIServer", "WindowManager", "Dock",
                                  "Control Center", "NotificationCenter"]
                if systemApps.contains(ownerName) { continue }
            }

            let windowX = boundsDict["X"] ?? 0
            let windowY = boundsDict["Y"] ?? 0
            let windowWidth = boundsDict["Width"] ?? 0
            let windowHeight = boundsDict["Height"] ?? 0

            let coversWidth = windowWidth >= screenWidth - 2

            // Traditional fullscreen: origin (0,0), covers entire screen
            // including menu bar. This catches in-app fullscreen (YouTube
            // F-key, etc.) even when the menu bar window is technically
            // present (it gets covered).
            let traditionalFS = abs(windowX) < 2 && abs(windowY) < 2
                && coversWidth && windowHeight >= screenHeight - 2

            // macOS 26 fullscreen Space: menu bar is NOT visible, window
            // starts at menu-bar edge and fills the remaining height.
            let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
            let modernFS = !menuBarVisible
                && abs(windowX) < 2
                && abs(windowY - menuBarHeight) < 4
                && coversWidth
                && windowHeight >= (screenHeight - menuBarHeight - 2)

            if traditionalFS || modernFS {
                return true
            }
        }

        return false
    }

    // MARK: - Teardown

    func teardown() {
        pollTimer?.invalidate()
        pollTimer = nil
        cancellables.removeAll()
    }
}
