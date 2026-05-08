import AppKit
import Combine
import Defaults

@MainActor
final class GestureHandler {
    static let shared = GestureHandler()

    private var globalMonitor: Any?
    private var localMonitor: Any?
    /// Per-panel pending auto-expand tasks. Keyed by ObjectIdentifier of the
    /// view model so multi-display panels each have their own dwell timer.
    private var pendingExpandTasks: [ObjectIdentifier: Task<Void, Never>] = [:]

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
            // .nonactivatingPanel routing means a click landing inside
            // our window can fire as either a global event (when the
            // panel isn't key — typical) or a local one. Dispatch via
            // the same path so wing-button clicks survive either route.
            handleGlobalClick(at: NSEvent.mouseLocation)

        case .keyDown:
            handleKeyDown(event)

        case .scrollWheel:
            handleScroll(event)

        default:
            break
        }
    }

    // MARK: - Mouse Handling

    /// Re-run hover logic at the current cursor position. Called after
    /// the hover debounce completes so the expand timer starts
    /// immediately if the cursor is already over the notch zone.
    func recheckCurrentPosition() {
        handleMouseMoved(at: NSEvent.mouseLocation)
    }

    private func handleMouseMoved(at point: NSPoint) {
        // Route to whichever panel owns the screen the cursor is on. In
        // single-display mode this is identical to reading `.shared`;
        // multi-display lets each panel hover/expand independently.
        guard let window = NotchWindowManager.shared.window(under: point) else {
            // Cursor is on a screen with no panel — collapse any panel
            // that's still in a hover state because the user clearly
            // moved away.
            for vm in NotchWindowManager.shared.viewModels.values where vm.currentState == .hovering {
                vm.collapse()
            }
            return
        }
        let viewModel = window.viewModel
        let screen = window.attachedScreen
        let geo = viewModel.notchGeometry

        guard geo.hasNotch || geo.isFloatingMode else { return }

        // The physical notch zone (covered area between wings)
        let notchZone = NSRect(
            x: screen.frame.midX - geo.notchWidth / 2,
            y: screen.frame.maxY - geo.notchHeight,
            width: geo.notchWidth,
            height: geo.notchHeight
        )

        // Wider hover detection zone around the notch — the area that
        // keeps the panel in the `.hovering` state (so wings can show
        // their hover-controls). Includes both wings.
        let hoverZone = NSRect(
            x: screen.frame.midX - (geo.notchWidth / 2 + viewModel.wingWidth),
            y: screen.frame.maxY - geo.notchHeight - 5,
            width: geo.notchWidth + viewModel.wingWidth * 2,
            height: geo.notchHeight + 5
        )

        // Auto-expand dwell trigger — notch body only. Hovering a wing
        // Wing hover also triggers expand — wing clicks now dispatch
        // in both hovering and expanded states, so the dwell-expand
        // no longer blocks control interaction.
        let expandZone = hoverZone

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
            // Auto-expand only while the cursor dwells on the notch body
            // itself — never on a wing. Wing hover stays in `.hovering`
            // so controls reveal and clicks dispatch via wingHitZones.
            let key = ObjectIdentifier(viewModel)
            if expandZone.contains(point) {
                if Defaults[.openNotchOnHover], pendingExpandTasks[key] == nil {
                    let duration = Defaults[.minimumHoverDuration]
                    let startTime = CFAbsoluteTimeGetCurrent()
                    viewModel.debugHoverDuration = duration
                    viewModel.debugHoverElapsed = 0
                    pendingExpandTasks[key] = Task { @MainActor [weak self, weak viewModel] in
                        // Tick the debug timer at 60fps until done
                        while !Task.isCancelled {
                            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                            viewModel?.debugHoverElapsed = elapsed
                            if elapsed >= duration { break }
                            try? await Task.sleep(for: .milliseconds(16))
                        }
                        guard !Task.isCancelled, let viewModel else { return }
                        if viewModel.currentState == .hovering {
                            viewModel.expand()
                        }
                        viewModel.debugHoverElapsed = 0
                        self?.pendingExpandTasks.removeValue(forKey: key)
                    }
                }
            } else {
                // Cursor moved off notch body (onto a wing or out
                // entirely) — drop any pending dwell. Wing hover keeps
                // the state as `.hovering` so controls stay live.
                pendingExpandTasks[key]?.cancel()
                pendingExpandTasks.removeValue(forKey: key)
                viewModel.debugHoverElapsed = 0
            }
            // Collapse back to idle when mouse leaves the wider hover zone
            if !hoverZone.contains(point) {
                pendingExpandTasks[key]?.cancel()
                pendingExpandTasks.removeValue(forKey: key)
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
        // Each panel handles its own outside-click collapse. A click on
        // screen A shouldn't dismiss screen B's open panel — and clicks
        // anywhere on the desktop should dismiss whichever panel is open
        // on that screen.
        guard let window = NotchWindowManager.shared.window(under: point) else {
            // Click on a screen with no panel still acts like an outside
            // click for any open panel.
            for vm in NotchWindowManager.shared.viewModels.values where vm.currentState == .expanded {
                vm.collapse()
            }
            return
        }
        let viewModel = window.viewModel
        let screen = window.attachedScreen

        switch viewModel.currentState {
        case .expanded:
            // Dispatch wing button clicks even while expanded (e.g.
            // KBO ticker/TTS toggles on the hovering wing).
            handleWingClick(at: point, viewModel: viewModel)

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
            handleWingClick(at: point, viewModel: viewModel)

        case .idle:
            break
        }
    }

    /// Hit-test the click against the wing buttons' actual SwiftUI
    /// frames, reported via PreferenceKey. No more hand-rolled geometry —
    /// when wing widths or button layouts change, the rects update
    /// automatically and clicks stay aligned with what the user sees.
    private func handleWingClick(at point: NSPoint, viewModel: NotchViewModel) {
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
        case .kboSoundToggle:
            (registry.widget(for: "kbo")?.wrapped as? KBOWidget)?
                .viewModel.soundEffectsEnabled.toggle()
        }
    }

    private func handleLocalClick() {
        // Click handling reserved for future use (e.g. playback controls)
    }

    // MARK: - Keyboard

    private func handleKeyDown(_ event: NSEvent) {
        switch event.keyCode {
        case 53: // Escape — collapse every open panel, regardless of which
                 // display it lives on.
            for vm in NotchWindowManager.shared.viewModels.values where vm.currentState != .idle {
                vm.collapse()
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
