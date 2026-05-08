import AppKit
import Defaults

/// Global mouse/keyboard event handler for the notch panel.
///
/// Adaptations from Mangtch's GestureHandler:
/// - Uses `AppDelegate` (accessed via `NSApplication.shared.delegate`) instead
///   of `NotchWindowManager` — boring.notch owns one window (`AppDelegate.window`)
///   or a dict (`AppDelegate.windows`) for multi-display.
/// - State machine: Mangtch's `.idle/.hovering/.expanded` maps to boring.notch's
///   `.closed/.open`; we treat "hovering" as a transient open state here.
/// - Wing dispatch: only music buttons wired; KBO buttons reserved for Phase 4.
@MainActor
final class GestureHandler {
    static let shared = GestureHandler()

    private var globalMonitor: Any?
    private var localMonitor: Any?

    private init() {}

    // MARK: - Setup / Teardown

    func start() {
        setupGlobalMonitor()
        setupLocalMonitor()
    }

    func stop() {
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
            // .nonactivatingPanel routing: clicks can arrive via either path.
            handleGlobalClick(at: NSEvent.mouseLocation)
        case .keyDown:
            handleKeyDown(event)
        case .scrollWheel:
            break // reserved
        default:
            break
        }
    }

    // MARK: - AppDelegate accessor

    /// Resolve our `AppDelegate` instance.
    ///
    /// SwiftUI's `@NSApplicationDelegateAdaptor` plants a private
    /// `SwiftUI.AppDelegate` wrapper as `NSApplication.shared.delegate` and
    /// proxies callbacks down to the wrapped instance — meaning the cast
    /// `delegate as? AppDelegate` returns nil even though our delegate IS
    /// the live one. We rely on the explicit `AppDelegate.shared` weak
    /// pointer (set in `applicationDidFinishLaunching`) to bypass the
    /// wrapper.
    private var appDelegate: AppDelegate? {
        AppDelegate.shared
    }

    /// Returns the view model whose window contains `point`, or nil.
    private func viewModel(under point: NSPoint) -> BoringViewModel? {
        guard let delegate = appDelegate else { return nil }

        if Defaults[.showOnAllDisplays] {
            // Find the screen that contains this point.
            for screen in NSScreen.screens {
                if screen.frame.contains(point),
                   let uuid = screen.displayUUID,
                   let vm = delegate.viewModels[uuid] {
                    return vm
                }
            }
        }
        // Single-display or fallback.
        if let window = delegate.window, window.screen?.frame.contains(point) == true {
            return delegate.vm
        }
        return delegate.vm
    }

    /// Returns all active view models.
    private var allViewModels: [BoringViewModel] {
        guard let delegate = appDelegate else { return [] }
        if Defaults[.showOnAllDisplays] {
            return Array(delegate.viewModels.values)
        }
        return [delegate.vm]
    }

    // MARK: - Mouse Handling

    func recheckCurrentPosition() {
        handleMouseMoved(at: NSEvent.mouseLocation)
    }

    private func handleMouseMoved(at point: NSPoint) {
        guard let vm = viewModel(under: point) else {
            // Cursor on a screen with no panel — collapse any non-closed
            // panels (.hovering as well as .open).
            for vm in allViewModels where vm.notchState != .closed {
                vm.close()
            }
            return
        }

        // Derive geometry from the screen the VM belongs to.
        guard let screen = screenFor(vm: vm) else { return }
        // Always use the hardware notch dimensions for hover zones — the VM's
        // notchSize stays at closedNotchSize even when open, but be explicit.
        let notchSize = vm.closedNotchSize

        // The notch zone (top-center strip at the notch width).
        let notchZone = NSRect(
            x: screen.frame.midX - notchSize.width / 2,
            y: screen.frame.maxY - notchSize.height,
            width: notchSize.width,
            height: notchSize.height
        )

        // Wider hover zone including wings.
        let m = vm.metrics
        let wingW = m.wingWidth
        // When open, hover zone must also cover the expanded panel body
        // so cursor moves / two-finger scroll into the panel don't trigger
        // close(). Panel height comes from the active widget's declaration.
        let extraOpenHeight: CGFloat = vm.notchState == .open ? m.totalHeight : 0
        let hoverZone = NSRect(
            x: notchZone.minX - wingW,
            y: notchZone.minY - 5 - extraOpenHeight,
            width: notchSize.width + wingW * 2,
            height: notchSize.height + 5 + extraOpenHeight
        )

        // Per-wing zones — fed into vm.hoveredWing so wings can show controls.
        let leftWingZone = NSRect(
            x: notchZone.minX - wingW,
            y: notchZone.minY - 5,
            width: wingW,
            height: notchSize.height + 5
        )
        let rightWingZone = NSRect(
            x: notchZone.maxX,
            y: notchZone.minY - 5,
            width: wingW,
            height: notchSize.height + 5
        )

        let newWingHover: HoveredWing
        if leftWingZone.contains(point) {
            newWingHover = .left
        } else if rightWingZone.contains(point) {
            newWingHover = .right
        } else {
            newWingHover = .none
        }
        if vm.hoveredWing != newWingHover {
            vm.hoveredWing = newWingHover
        }

        switch vm.notchState {
        case .closed:
            // Cursor enters wing/notch zone → reveal hover affordances (wing controls).
            if hoverZone.contains(point) {
                vm.hover()
            }

        case .hovering:
            // Cursor escaped the wing+notch hover footprint → drop back to fully closed.
            if !hoverZone.contains(point) {
                vm.close()
            }

        case .open:
            // Panel stays open until pan-up gesture, outside click, or Escape.
            break
        }
    }

    private func handleGlobalClick(at point: NSPoint) {
        guard let vm = viewModel(under: point) else {
            for vm in allViewModels where vm.notchState != .closed {
                vm.close()
            }
            return
        }

        switch vm.notchState {
        case .open, .hovering:
            // Wing controls live on both .hovering and .open — the
            // transport buttons fade in on hover and stay during the
            // expanded panel. Dispatch wing-button clicks in either state.
            handleWingClick(at: point, viewModel: vm)

        case .closed:
            break
        }
    }

    private func handleWingClick(at point: NSPoint, viewModel: BoringViewModel) {
        guard let zone = viewModel.wingHitZones.first(where: { $0.rect.contains(point) })
        else { return }
        dispatch(zone.button)
    }

    private func dispatch(_ button: WingButton) {
        switch button {
        case .musicPrev:
            MusicManager.shared.previousTrack()
        case .musicPlayPause:
            MusicManager.shared.playPause()
        case .musicNext:
            MusicManager.shared.nextTrack()
        case .kboTickerToggle:
            if let widget = WidgetRegistry.shared.widget(for: "kbo"),
               let kboWidget = widget.wrapped as? KBOWidget {
                kboWidget.viewModel.tickerEnabled.toggle()
            }
        case .kboTTSToggle:
            if let widget = WidgetRegistry.shared.widget(for: "kbo"),
               let kboWidget = widget.wrapped as? KBOWidget {
                kboWidget.viewModel.ttsEnabled.toggle()
            }
        case .kboSoundToggle:
            if let widget = WidgetRegistry.shared.widget(for: "kbo"),
               let kboWidget = widget.wrapped as? KBOWidget {
                kboWidget.viewModel.soundEffectsEnabled.toggle()
            }
        }
    }

    // MARK: - Keyboard

    private func handleKeyDown(_ event: NSEvent) {
        switch event.keyCode {
        case 53: // Escape — collapse every non-closed panel (.hovering and .open)
            for vm in allViewModels where vm.notchState != .closed {
                vm.close()
            }
        default:
            break
        }
    }

    // MARK: - Helpers

    private func screenFor(vm: BoringViewModel) -> NSScreen? {
        guard let uuid = vm.screenUUID else { return NSScreen.main }
        return NSScreen.screen(withUUID: uuid) ?? NSScreen.main
    }
}
