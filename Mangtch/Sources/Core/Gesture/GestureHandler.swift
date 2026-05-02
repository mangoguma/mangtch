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

    /// Map a click in the .hovering state to the underlying wing-button
    /// action. Geometry below mirrors the SwiftUI layout in
    /// CompactArtworkView (left wing) and KBORightWingView (right wing).
    private func handleWingClick(at point: NSPoint) {
        guard let screen = NSScreen.screens.first else { return }
        let viewModel = NotchViewModel.shared
        let geo = viewModel.notchGeometry
        let halfNotch = geo.notchWidth / 2
        let wingHeight = geo.notchHeight + 5
        let wingTopY = screen.frame.maxY
        let wingBottomY = wingTopY - wingHeight
        guard point.y >= wingBottomY, point.y <= wingTopY else { return }

        let leftWingMinX = screen.frame.midX - halfNotch - viewModel.wingWidth
        let rightWingMinX = screen.frame.midX + halfNotch

        if point.x >= leftWingMinX, point.x < leftWingMinX + viewModel.wingWidth {
            dispatchLeftWingClick(relativeX: point.x - leftWingMinX)
        } else if point.x >= rightWingMinX, point.x < rightWingMinX + viewModel.wingWidth {
            dispatchRightWingClick(relativeX: point.x - rightWingMinX)
        }
    }

    /// Music transport: 3 icons (back 22, play 26, forward 22) with 2pt
    /// spacing, total 74pt, centered in the 120pt wing — starts at x=23.
    private func dispatchLeftWingClick(relativeX: CGFloat) {
        guard relativeX >= 23, relativeX <= 97 else { return }
        guard let widget = WidgetRegistry.shared.widget(for: "music-player")?.wrapped as? MusicPlayerWidget else { return }
        let vm = widget.viewModel
        if relativeX < 47 {
            vm.previousTrack()
        } else if relativeX < 75 {
            vm.togglePlayPause()
        } else {
            vm.nextTrack()
        }
    }

    /// KBO toggle bar: 2 icons (28pt each) with 6pt spacing, total 62pt,
    /// centered in 120pt wing — starts at x=29. Only relevant when KBO
    /// is the active widget.
    private func dispatchRightWingClick(relativeX: CGFloat) {
        guard relativeX >= 29, relativeX <= 91 else { return }
        let viewModel = NotchViewModel.shared
        guard viewModel.currentExpandedWidgetID == "kbo",
              let kbo = (WidgetRegistry.shared.widget(for: "kbo")?.wrapped as? KBOWidget)?.viewModel
        else { return }
        if relativeX < 63 {
            kbo.tickerEnabled.toggle()
        } else {
            kbo.ttsEnabled.toggle()
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
