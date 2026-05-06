import AppKit
import SwiftUI
import Combine
import Defaults
import Observation

final class NotchWindow: NSPanel {
    /// Convenience accessor that resolves to the primary panel via the
    /// manager. External callers (drag detector, music VM, etc.) only
    /// need the canonical instance; multi-display fan-out is a manager
    /// concern.
    @MainActor
    static var shared: NotchWindow { NotchWindowManager.shared.primaryWindow }

    let viewModel: NotchViewModel
    /// The display this panel is anchored to. Frame/screen lookups go
    /// through here instead of the global resolver so a panel that owns
    /// an external display keeps using *its* coordinates even if the
    /// user changes the primary in Settings.
    ///
    /// Mutable because `NSScreen.screens` replaces instances on display
    /// topology changes — without refreshing this reference, a surviving
    /// panel keeps reading the *old* `frame` and ends up drawn on the
    /// wrong monitor (two panels stacking on one display in 3-monitor
    /// setups). `NotchWindowManager.sync()` rebinds this to the fresh
    /// NSScreen matching our UUID.
    private(set) var attachedScreen: NSScreen

    @MainActor
    func rebind(to screen: NSScreen) {
        self.attachedScreen = screen
    }

    private var cancellables = Set<AnyCancellable>()
    private var panelWidthObservation: Any?
    private var expandedHeightObservation: Any?
    private var fullscreenObservation: Any?
    private let fullscreenObserver = FullscreenObserver()
    private var allowKeyWindow = false
    private var didSetup = false

    init(screen: NSScreen, viewModel: NotchViewModel) {
        self.viewModel = viewModel
        self.attachedScreen = screen
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        configureWindow()
    }

    // MARK: - Configuration

    private func configureWindow() {
        // Window behavior — use .mainMenu + 3 so the notch sits above menu bar
        // but with isFloatingPanel + canBecomeKey=false (idle/hover) to avoid
        // blocking menu bar item clicks.
        // NOTE: isFloatingPanel must be set BEFORE level — it resets the
        // window level to kCGFloatingWindowLevel (3), which would put us
        // behind the menu bar.
        self.isFloatingPanel = true
        self.level = .mainMenu + 3
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = false
        self.isMovableByWindowBackground = false
        self.hidesOnDeactivate = false
        self.animationBehavior = .none
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
    }

    // MARK: - Setup

    @MainActor
    func setup() {
        // Idempotent — manager.sync() may call this every screen-change
        // notification. Repeat invocations only refresh the frame.
        if didSetup {
            updateWindowFrame()
            return
        }

        let screen = self.attachedScreen
        NSLog("[NotchWindow] Setting up on screen: \(screen.localizedName)")
        let geo = NotchGeometry.detect(for: screen)

        if geo.hasNotch {
            NSLog("[NotchWindow] ✓ Notch detected! notchHeight=\(geo.notchHeight)")
        } else if geo.isFloatingMode {
            NSLog("[NotchWindow] ℹ️ No notch — using floating panel mode")
        } else {
            NSLog("[NotchWindow] No screen geometry available.")
            return
        }

        // Set initial frame to match current content height (just notchHeight)
        updateWindowFrame()

        NSLog("[NotchWindow] Panel frame set")

        // Custom NSHostingView subclass that returns acceptsFirstMouse=true
        // so the first click in our non-key panel is delivered as a real
        // mouseDown to SwiftUI views (default behaviour is to swallow it
        // as a window-activation click).
        let swiftUIContent = NotchContentView(viewModel: self.viewModel, hostWindow: self)
        let hostingView = FirstMouseHostingView(rootView: swiftUIContent)
        hostingView.frame = self.contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
        self.contentView = hostingView

        // Note: we deliberately do NOT call self.registerForDraggedTypes
        // here. Doing so makes AppKit absorb mouseDown events on the
        // contentView (looking for a drag-start gesture) which kills every
        // SwiftUI Button click on the wings. Drag-from-Finder is detected
        // separately by the global leftMouseDragged monitor below, and the
        // actual drop handling lives in SwiftUI .onDrop modifiers.
        self.orderFrontRegardless()

        NSLog("[NotchWindow] ✓ Window setup complete and visible")

        didSetup = true
        setupStateObserver()
        setupPanelWidthObserver()
        setupExpandedHeightObserver()
        setupFullscreenObserver()
        // Sync initial fullscreen state after a brief delay — at launch
        // Mangtch is briefly frontmost (activate call in AppDelegate) so
        // the observer's immediate check() skips. By 1s the system has
        // settled and the real frontmost app is visible.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            self?.handleFullscreenChange()
        }
        // External file-drag detection lives in `DragDetector`, which
        // already routes per-screen via `NotchWindowManager.window(under:)`.
        // We used to install a duplicate monitor here for the primary
        // panel; removing it avoids two `forceExpand` calls per drag.
    }

    // MARK: - Dynamic Window Sizing

    /// Recalculate window frame to match visible content only.
    /// This prevents the window from covering clickable areas below.
    @MainActor
    private func updateWindowFrame() {
        let screen = self.attachedScreen
        let geo = self.viewModel.notchGeometry
        let viewModel = self.viewModel

        // Window dimensions = only what's visible + small margin for shadow
        let contentHeight: CGFloat = geo.notchHeight + viewModel.expandedHeight
        let margin: CGFloat = viewModel.currentState == .expanded ? 30 : 10
        let panelHeight: CGFloat = contentHeight + margin

        // +50pt margin (was +40) absorbs sub-frame drift between AppKit's
        // instant `setFrame` and SwiftUI's `withAnimation` interpolation on
        // `panelWidth`. Width-only changes mid-`.expanded` (e.g. KBO opening
        // its linescore) animate via `animateWindowFrame`; the larger margin
        // hides any easing-curve mismatch between the two timing systems.
        let targetWidth: CGFloat = viewModel.panelWidth + 50

        let panelX = screen.frame.midX - targetWidth / 2

        // Top-align in both modes. In notch mode the wings tuck under
        // the safe area (notchHeight); in floating mode they sit in the
        // menu-bar slot, so the same `maxY - panelHeight` is correct.
        let panelY: CGFloat = screen.frame.maxY - panelHeight

        let frame = NSRect(x: panelX, y: panelY, width: targetWidth, height: panelHeight)
        self.setFrame(frame, display: true)
    }

    // MARK: - State-Based Behavior

    private func setupStateObserver() {
        EventBus.shared.stateChanges
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.handleStateChange(state)
            }
            .store(in: &cancellables)

        // Reposition when screen geometry changes (display connect/disconnect)
        // OR when the user picks a different display in Settings —
        // NotchViewModel emits `.screenChanged` for both paths.
        EventBus.shared.on { event -> Void? in
            if case .screenChanged = event { return () } else { return nil }
        }
        .sink { [weak self] _ in
            Task { @MainActor in
                self?.updateWindowFrame()
            }
        }
        .store(in: &cancellables)
    }

    private func handleStateChange(_ state: NotchState) {
        let previousState = self.viewModel.previousState

        switch state {
        case .idle:
            self.ignoresMouseEvents = false
            allowKeyWindow = false
            // Resign key so menu bar items become clickable again
            if self.isKeyWindow { self.resignKey() }
        case .hovering:
            self.ignoresMouseEvents = false
            allowKeyWindow = false
            if self.isKeyWindow { self.resignKey() }
        case .expanded:
            self.ignoresMouseEvents = false
            allowKeyWindow = true
        }

        // Resize window to match new content height.
        // When collapsing from expanded, animate the window frame shrink
        // in sync with the SwiftUI collapse spring (instead of a hardcoded delay).
        let isCollapsing = previousState == .expanded && (state == .idle || state == .hovering)
        let isExpanding = !isCollapsing && state == .expanded

        if isCollapsing {
            animateWindowFrame(duration: 0.4)
        } else if isExpanding {
            // Pre-expand the NSPanel to the full target size BEFORE the
            // SwiftUI animation starts. Otherwise the observation-driven
            // updateWindowFrame lags behind SwiftUI rendering, clipping
            // the wings/panel during the transition.
            preExpandWindowFrame()
        } else {
            updateWindowFrame()
        }
    }

    /// Set the NSPanel frame to the fully-expanded size immediately,
    /// before SwiftUI starts animating. This reserves enough room so
    /// wing/panel content never clips during the grow animation.
    @MainActor
    private func preExpandWindowFrame() {
        let screen = self.attachedScreen
        let geo = self.viewModel.notchGeometry
        let vm = self.viewModel

        let targetWing = max(vm.wingWidth, NotchViewModel.minWingWidth)
        let fullPanelWidth = geo.notchWidth + targetWing * 2
        let fullHeight = geo.notchHeight + vm.maxExpandedHeight + vm.additionalExpandedHeight + 30

        let targetWidth = fullPanelWidth + 40
        let panelX = screen.frame.midX - targetWidth / 2
        let panelY = screen.frame.maxY - fullHeight

        let frame = NSRect(x: panelX, y: panelY, width: targetWidth, height: fullHeight)
        self.setFrame(frame, display: true)
    }

    /// Smoothly animate the NSPanel frame to the target size.
    /// Duration should match the collapse spring's response time.
    @MainActor
    private func animateWindowFrame(duration: TimeInterval) {
        let screen = self.attachedScreen
        let geo = self.viewModel.notchGeometry
        let viewModel = self.viewModel

        let contentHeight: CGFloat = geo.notchHeight + viewModel.expandedHeight
        let margin: CGFloat = viewModel.currentState == .expanded ? 30 : 10
        let panelHeight: CGFloat = contentHeight + margin

        // +50pt margin (was +40) absorbs sub-frame drift between AppKit's
        // instant `setFrame` and SwiftUI's `withAnimation` interpolation on
        // `panelWidth`. Width-only changes mid-`.expanded` (e.g. KBO opening
        // its linescore) animate via `animateWindowFrame`; the larger margin
        // hides any easing-curve mismatch between the two timing systems.
        let targetWidth: CGFloat = viewModel.panelWidth + 50

        let panelX = screen.frame.midX - targetWidth / 2
        // Top-align in both modes. In notch mode the wings tuck under
        // the safe area (notchHeight); in floating mode they sit in the
        // menu-bar slot, so the same `maxY - panelHeight` is correct.
        let panelY: CGFloat = screen.frame.maxY - panelHeight

        let targetFrame = NSRect(x: panelX, y: panelY, width: targetWidth, height: panelHeight)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.animator().setFrame(targetFrame, display: true)
        }
    }

    // MARK: - Panel Width Observer

    private func setupPanelWidthObserver() {
        panelWidthObservation = withObservationTracking {
            _ = self.viewModel.panelWidth
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                // Width-only changes that fire while the panel is already
                // expanded (e.g. KBO opening its linescore mid-session)
                // animate the NSPanel frame so it stays in lockstep with
                // SwiftUI's `withAnimation` on `panelWidth`. State
                // transitions handle the frame separately via
                // `handleStateChange`, so an instant snap there is fine.
                if self.viewModel.currentState == .expanded {
                    self.animateWindowFrame(duration: 0.22)
                } else {
                    self.updateWindowFrame()
                }
                self.setupPanelWidthObserver()
            }
        }
    }

    // MARK: - Expanded Height Observer

    private func setupExpandedHeightObserver() {
        expandedHeightObservation = withObservationTracking {
            _ = self.viewModel.expandedHeight
        } onChange: { [weak self] in
            Task { @MainActor in
                // State transitions (idle ↔ hovering ↔ expanded) drive the
                // frame update through handleStateChange, which animates with
                // the matching spring. If we ALSO snap the frame here, the
                // window collapses instantly while SwiftUI is still animating
                // the content down — the panel briefly clips visible content.
                // Only react to expandedHeight changes that aren't part of a
                // state transition (e.g. screen-geometry shifts).
                if self?.viewModel.currentState == .expanded {
                    self?.updateWindowFrame()
                }
                self?.setupExpandedHeightObserver()
            }
        }
    }

    // MARK: - Fullscreen Observer

    private func setupFullscreenObserver() {
        fullscreenObservation = withObservationTracking {
            _ = self.fullscreenObserver.isFullscreenAppActive
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.handleFullscreenChange()
                self?.setupFullscreenObserver()
            }
        }

        // Also react when user toggles hideInFullscreen in Settings
        Defaults.publisher(.hideInFullscreen)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.handleFullscreenChange()
                }
            }
            .store(in: &cancellables)
    }

    private func handleFullscreenChange() {
        guard SettingsManager.shared.hideInFullscreen else {
            if !self.isVisible { self.orderFrontRegardless() }
            return
        }

        if fullscreenObserver.isFullscreenAppActive {
            NSLog("[NotchWindow] Fullscreen → hiding panel")
            self.orderOut(nil)
        } else {
            NSLog("[NotchWindow] Normal → showing panel")
            self.orderFrontRegardless()
        }
    }

    // MARK: - Window Behavior Overrides

    override var canBecomeKey: Bool { allowKeyWindow }
    override var canBecomeMain: Bool { false }

    // Prevent macOS from clamping the window to the visible frame.
    // Without this, the system moves the window below the notch/menu bar area.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }

    override func resignKey() {
        super.resignKey()
    }

    // MARK: - Repositioning

    @MainActor
    func reposition() {
        updateWindowFrame()
    }
}

private final class FirstMouseHostingView: NSHostingView<NotchContentView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

