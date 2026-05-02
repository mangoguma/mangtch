import AppKit
import Combine

@MainActor
final class GestureHandler {
    static let shared = GestureHandler()

    private var globalMonitor: Any?
    private var localMonitor: Any?

    private init() {}

    // MARK: - Setup

    func setup() {
        setupGlobalMonitor()
        setupLocalMonitor()
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

        // Per-wing hover detection — fed to wing views so they can flip
        // between info/artwork and hover-controls. Active in any state
        // (idle/hovering/expanded) since the wings stay visible always.
        let leftWingZone = NSRect(
            x: screen.frame.midX - geo.notchWidth / 2 - viewModel.wingWidth,
            y: screen.frame.maxY - geo.notchHeight - 5,
            width: viewModel.wingWidth,
            height: geo.notchHeight + 5
        )
        let rightWingZone = NSRect(
            x: screen.frame.midX + geo.notchWidth / 2,
            y: screen.frame.maxY - geo.notchHeight - 5,
            width: viewModel.wingWidth,
            height: geo.notchHeight + 5
        )
        let newWingHover: NotchViewModel.WingHover
        if leftWingZone.contains(point) {
            newWingHover = .left
        } else if rightWingZone.contains(point) {
            newWingHover = .right
        } else {
            newWingHover = .none
        }
        if viewModel.hoveredWing != newWingHover {
            viewModel.hoveredWing = newWingHover
        }

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
                y: screen.frame.maxY - geo.notchHeight - viewModel.effectiveExpandedHeight,
                width: panelWidth,
                height: viewModel.effectiveExpandedHeight + geo.notchHeight + 10
            )

            if !expandedZone.contains(point) {
                viewModel.collapse()
            }
        }
    }

    private func handleGlobalClick(at point: NSPoint) {
        let viewModel = NotchViewModel.shared

        switch viewModel.currentState {
        case .expanded:
            // Click outside the expanded panel collapses it.
            guard let screen = NSScreen.screens.first else { return }
            let geo = viewModel.notchGeometry
            let panelRect = NSRect(
                x: screen.frame.midX - viewModel.panelWidth / 2,
                y: screen.frame.maxY - geo.notchHeight - viewModel.effectiveExpandedHeight,
                width: viewModel.panelWidth,
                height: viewModel.effectiveExpandedHeight + geo.notchHeight
            )
            if !panelRect.contains(point) {
                viewModel.collapse()
            }

        case .hovering:
            // The notch panel is a .nonactivatingPanel and stays non-key
            // during hover, which means SwiftUI Button / .onTapGesture
            // never fires for clicks on the wing controls — macOS routes
            // the click as a window-activation gesture instead. Dispatch
            // the click to the right action manually based on which wing
            // and where within it the cursor landed.
            handleWingClick(at: point)

        case .idle:
            break
        }
    }

    /// Hit-test the click against the wing buttons' actual SwiftUI
    /// frames, reported via PreferenceKey. No more hand-rolled geometry —
    /// when wing widths or button layouts change, the rects update
    /// automatically and clicks stay aligned with what the user sees.
    private func handleWingClick(at point: NSPoint) {
        let viewModel = NotchViewModel.shared
        guard let zone = viewModel.wingHitZones.first(where: { $0.rect.contains(point) })
        else { return }
        dispatch(zone.button)
    }

    private func dispatch(_ button: WingButton) {
        let registry = WidgetRegistry.shared
        switch button {
        case .musicPrev:
            (registry.widget(for: "music-player")?.wrapped as? MusicPlayerWidget)?
                .viewModel.previousTrack()
        case .musicPlayPause:
            (registry.widget(for: "music-player")?.wrapped as? MusicPlayerWidget)?
                .viewModel.togglePlayPause()
        case .musicNext:
            (registry.widget(for: "music-player")?.wrapped as? MusicPlayerWidget)?
                .viewModel.nextTrack()
        case .kboTickerToggle:
            (registry.widget(for: "kbo")?.wrapped as? KBOWidget)?
                .viewModel.tickerEnabled.toggle()
        case .kboTTSToggle:
            (registry.widget(for: "kbo")?.wrapped as? KBOWidget)?
                .viewModel.ttsEnabled.toggle()
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
