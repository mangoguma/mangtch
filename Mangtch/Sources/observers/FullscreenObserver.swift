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

        // macOS 26: fullscreen apps have a backdrop window at layer -1
        // covering the entire screen. Maximized apps don't. This is
        // more reliable than menu-bar presence since macOS 26 can show
        // the menu bar in fullscreen.
        let hasFullscreenBackdrop = windowList.contains { info in
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t ?? 0
            guard layer == -1, ownerPID != excludePID else { return false }
            guard let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] else { return false }
            let w = bounds["Width"] ?? 0
            let h = bounds["Height"] ?? 0
            return w >= screenWidth - 2 && h >= screenHeight - 2
        }

        if hasFullscreenBackdrop { return true }

        // Traditional fullscreen: a layer-0 window at origin (0,0)
        // covering the entire screen (including menu bar area).
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

            if abs(windowX) < 2 && abs(windowY) < 2
                && windowWidth >= screenWidth - 2
                && windowHeight >= screenHeight - 2 {
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
