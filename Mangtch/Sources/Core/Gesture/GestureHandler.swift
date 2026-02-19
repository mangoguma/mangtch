import AppKit
import Combine
import CoreAudio

@MainActor
final class GestureHandler {
    static let shared = GestureHandler()

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private var systemHUDSuppressor: SystemHUDSuppressor?

    private init() {
        setupSettingsObserver()
    }

    private func setupSettingsObserver() {
        // Observe changes to suppressSystemHUD setting
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.setupSystemHUDSuppression()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Setup

    func setup() {
        setupGlobalMonitor()
        setupLocalMonitor()
        setupSystemHUDSuppression()
    }

    func teardown() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        systemHUDSuppressor?.stop()
        systemHUDSuppressor = nil
    }

    // MARK: - System HUD Suppression (OSD hiding only)

    private func setupSystemHUDSuppression() {
        // SystemHUDSuppressor is only used for hiding the native macOS OSD.
        // Volume/brightness change detection is handled by SystemInfoBridge
        // via CoreAudio property listeners (no accessibility permissions needed).
        guard SettingsManager.shared.suppressSystemHUD else {
            systemHUDSuppressor?.stop()
            systemHUDSuppressor = nil
            return
        }

        let suppressor = SystemHUDSuppressor()
        if suppressor.start(hideOSD: true) {
            systemHUDSuppressor = suppressor
            print("[GestureHandler] SystemHUDSuppressor started (OSD hidden)")
        } else {
            print("[GestureHandler] SystemHUDSuppressor failed to start")
        }
    }

    // MARK: - Global Monitor (events outside our app)

    private func setupGlobalMonitor() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDown]
        ) { [weak self] event in
            let eventType = event.type
            let mouseLocation = NSEvent.mouseLocation
            Task { @MainActor in
                switch eventType {
                case .mouseMoved:
                    self?.handleMouseMoved(at: mouseLocation)
                case .leftMouseDown:
                    self?.handleGlobalClick(at: mouseLocation)
                default:
                    break
                }
            }
        }
    }

    private func handleGlobalEvent(_ event: NSEvent) {
        switch event.type {
        case .mouseMoved:
            handleMouseMoved(at: NSEvent.mouseLocation)
        case .leftMouseDown:
            handleGlobalClick(at: NSEvent.mouseLocation)
        default:
            break
        }
    }

    // MARK: - Local Monitor (events in our app)

    private func setupLocalMonitor() {
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDown, .keyDown, .scrollWheel]
        ) { [weak self] event in
            Task { @MainActor in
                self?.handleLocalEvent(event)
            }
            return event
        }
    }

    private func handleLocalEvent(_ event: NSEvent) {
        switch event.type {
        case .mouseMoved:
            handleMouseMoved(at: NSEvent.mouseLocation)

        case .leftMouseDown:
            handleLocalClick()

        case .keyDown:
            handleKeyDown(event)

        case .scrollWheel:
            handleScroll(event)

        default:
            break
        }
    }

    // MARK: - Mouse Handling

    private func handleMouseMoved(at point: NSPoint) {
        let viewModel = NotchViewModel.shared
        let geo = viewModel.notchGeometry

        guard geo.hasNotch, let screen = NSScreen.screens.first else { return }

        // The physical notch zone (covered area between wings)
        let notchZone = NSRect(
            x: screen.frame.midX - geo.notchWidth / 2,
            y: screen.frame.maxY - geo.notchHeight,
            width: geo.notchWidth,
            height: geo.notchHeight
        )

        // Wider hover detection zone around the notch
        let hoverZone = NSRect(
            x: screen.frame.midX - (geo.notchWidth / 2 + viewModel.wingWidth),
            y: screen.frame.maxY - geo.notchHeight - 5,
            width: geo.notchWidth + viewModel.wingWidth * 2,
            height: geo.notchHeight + 5
        )

        switch viewModel.currentState {
        case .idle:
            // Enter hovering when mouse enters the hover zone around the notch
            if hoverZone.contains(point) {
                viewModel.hover()
            }

        case .hovering:
            // Expand when hovering over the notch's covered area
            if notchZone.contains(point) {
                viewModel.expand()
            }
            // Collapse back to idle when mouse leaves the hover zone
            if !hoverZone.contains(point) {
                viewModel.collapse()
            }

        case .expanded:
            // Collapse when mouse leaves the entire panel area
            let panelWidth = viewModel.panelWidth + 40
            let expandedZone = NSRect(
                x: screen.frame.midX - panelWidth / 2,
                y: screen.frame.maxY - geo.notchHeight - viewModel.maxExpandedHeight,
                width: panelWidth,
                height: viewModel.maxExpandedHeight + geo.notchHeight + 10
            )

            if !expandedZone.contains(point) {
                viewModel.collapse()
            }
        }
    }

    private func handleGlobalClick(at point: NSPoint) {
        let viewModel = NotchViewModel.shared
        guard viewModel.currentState == .expanded else { return }

        guard let screen = NSScreen.screens.first else { return }
        let geo = viewModel.notchGeometry

        // Check if click is outside the expanded panel
        let panelRect = NSRect(
            x: screen.frame.midX - viewModel.panelWidth / 2,
            y: screen.frame.maxY - geo.notchHeight - viewModel.maxExpandedHeight,
            width: viewModel.panelWidth,
            height: viewModel.maxExpandedHeight + geo.notchHeight
        )

        if !panelRect.contains(point) {
            viewModel.collapse()
        }
    }

    private func handleLocalClick() {
        // Click handling reserved for future use (e.g. playback controls)
    }

    // MARK: - Keyboard

    private func handleKeyDown(_ event: NSEvent) {
        switch event.keyCode {
        case 53: // Escape
            if NotchViewModel.shared.currentState != .idle {
                NotchViewModel.shared.collapse()
            }
        default:
            break
        }
    }

    // MARK: - Scroll

    private func handleScroll(_ event: NSEvent) {
        // Future: volume control via scroll over notch
    }
}
