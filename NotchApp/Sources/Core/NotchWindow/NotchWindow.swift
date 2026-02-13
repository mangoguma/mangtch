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
        // Window behavior
        self.level = .statusBar + 1
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
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

        // Host SwiftUI content
        let swiftUIContent = NotchContentView()
        let hostingView = NSHostingView(rootView: swiftUIContent)
        hostingView.frame = self.contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
        self.contentView = hostingView

        self.orderFrontRegardless()

        NSLog("[NotchWindow] ✓ Window setup complete and visible")

        setupStateObserver()
        setupPanelWidthObserver()
        setupExpandedHeightObserver()
        setupHUDVisibilityObserver()
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

        // Always keep window wide enough for both wings to avoid resize jank.
        // SwiftUI handles which wings are actually visible via opacity/transitions.
        let fullWidth = geo.notchWidth + (viewModel.wingWidth * 2) + 40
        let targetWidth: CGFloat
        if viewModel.isHUDVisible {
            targetWidth = max(fullWidth, 320)
        } else {
            targetWidth = fullWidth
        }

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
        switch state {
        case .idle:
            // Left wing still visible and interactive in idle
            self.ignoresMouseEvents = false
        case .hovering:
            self.ignoresMouseEvents = false
        case .expanded:
            self.ignoresMouseEvents = false
        }
        // Resize window to match new content height
        Task { @MainActor in
            self.updateWindowFrame()
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

    // MARK: - Window Behavior Overrides

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
    }

    // MARK: - Repositioning

    @MainActor
    func reposition() {
        updateWindowFrame()
    }
}
