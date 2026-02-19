import AppKit
import SwiftUI
import Combine
import Observation

final class NotchWindow: NSPanel {
    static let shared = NotchWindow()
    private var cancellables = Set<AnyCancellable>()
    private var panelWidthObservation: Any?
    private var expandedHeightObservation: Any?
    private var hudVisibilityObservation: Any?
    private var fullscreenObservation: Any?
    private let fullscreenObserver = FullscreenObserver()
    private var hostingController: NSHostingController<NotchContentView>?
    private var allowKeyWindow = false

    private init() {
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
        self.level = .mainMenu + 3
        self.isFloatingPanel = true
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
        guard let screen = NSScreen.screens.first else {
            NSLog("[NotchWindow] No screens found, retrying in 0.5 seconds...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                Task { @MainActor in
                    self.setup()
                }
            }
            return
        }

        NSLog("[NotchWindow] ✓ Screen found (screens[0])")
        let geo = NotchGeometry.detect()

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

        // Host SwiftUI content — use NSHostingController with safeAreaRegions = []
        // to prevent macOS from applying notch safe area insets
        let swiftUIContent = NotchContentView()
        let controller = NSHostingController(rootView: swiftUIContent)
        controller.safeAreaRegions = []
        self.hostingController = controller
        let hostingView = controller.view
        hostingView.frame = self.contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
        self.contentView = hostingView

        self.orderFrontRegardless()

        NSLog("[NotchWindow] ✓ Window setup complete and visible")

        setupStateObserver()
        setupPanelWidthObserver()
        setupExpandedHeightObserver()
        setupHUDVisibilityObserver()
        setupFullscreenObserver()
    }

    // MARK: - Dynamic Window Sizing

    /// Recalculate window frame to match visible content only.
    /// This prevents the window from covering clickable areas below.
    @MainActor
    private func updateWindowFrame() {
        guard let screen = NSScreen.screens.first else { return }
        let geo = NotchViewModel.shared.notchGeometry
        let viewModel = NotchViewModel.shared

        // Window dimensions = only what's visible + small margin for shadow/HUD
        let contentHeight: CGFloat = geo.notchHeight + viewModel.expandedHeight
        let hudExtra: CGFloat = viewModel.isHUDVisible ? 50 : 0
        let margin: CGFloat = viewModel.currentState == .expanded ? 30 : 10
        let panelHeight: CGFloat = contentHeight + hudExtra + margin

        let targetWidth: CGFloat
        if viewModel.isHUDVisible {
            targetWidth = max(viewModel.panelWidth + 40, 320)
        } else {
            targetWidth = viewModel.panelWidth + 40
        }

        // Always center since both wings are always visible
        let panelX = screen.frame.midX - targetWidth / 2

        let panelY: CGFloat
        if geo.isFloatingMode {
            panelY = screen.frame.maxY - panelHeight - 25
        } else {
            panelY = screen.frame.maxY - panelHeight
        }

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
    }

    private func handleStateChange(_ state: NotchState) {
        let previousState = NotchViewModel.shared.previousState

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

        if isCollapsing {
            animateWindowFrame(duration: 0.65)
        } else {
            updateWindowFrame()
        }
    }

    /// Smoothly animate the NSPanel frame to the target size.
    /// Duration should match the collapse spring's response time.
    @MainActor
    private func animateWindowFrame(duration: TimeInterval) {
        guard let screen = NSScreen.screens.first else { return }
        let geo = NotchViewModel.shared.notchGeometry
        let viewModel = NotchViewModel.shared

        let contentHeight: CGFloat = geo.notchHeight + viewModel.expandedHeight
        let hudExtra: CGFloat = viewModel.isHUDVisible ? 50 : 0
        let margin: CGFloat = viewModel.currentState == .expanded ? 30 : 10
        let panelHeight: CGFloat = contentHeight + hudExtra + margin

        let targetWidth: CGFloat
        if viewModel.isHUDVisible {
            targetWidth = max(viewModel.panelWidth + 40, 320)
        } else {
            targetWidth = viewModel.panelWidth + 40
        }

        let panelX = screen.frame.midX - targetWidth / 2
        let panelY: CGFloat
        if geo.isFloatingMode {
            panelY = screen.frame.maxY - panelHeight - 25
        } else {
            panelY = screen.frame.maxY - panelHeight
        }

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
            _ = NotchViewModel.shared.panelWidth
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateWindowFrame()
                self?.setupPanelWidthObserver()
            }
        }
    }

    // MARK: - Expanded Height Observer

    private func setupExpandedHeightObserver() {
        expandedHeightObservation = withObservationTracking {
            _ = NotchViewModel.shared.expandedHeight
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateWindowFrame()
                self?.setupExpandedHeightObserver()
            }
        }
    }

    // MARK: - HUD Visibility Observer

    private func setupHUDVisibilityObserver() {
        hudVisibilityObservation = withObservationTracking {
            _ = NotchViewModel.shared.isHUDVisible
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateWindowFrame()
                self?.setupHUDVisibilityObserver()
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
