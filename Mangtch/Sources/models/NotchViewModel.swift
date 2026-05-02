import SwiftUI
import Combine

@Observable
@MainActor
final class NotchViewModel {
    // MARK: - Singleton
    static let shared = NotchViewModel()

    // MARK: - State

    private(set) var currentState: NotchState = .idle
    private(set) var previousState: NotchState = .idle
    private(set) var notchGeometry: NotchGeometry

    /// Current expanded panel height (animated)
    var expandedHeight: CGFloat = 0

    /// Current panel width (animated)
    var panelWidth: CGFloat = 0

    /// ID of the widget currently shown in the expanded panel. Persists
    /// across sessions via SettingsManager.lastExpandedWidgetID. Defaults
    /// to "music-player" on first run.
    var currentExpandedWidgetID: String {
        didSet {
            guard oldValue != currentExpandedWidgetID else { return }
            SettingsManager.shared.lastExpandedWidgetID = currentExpandedWidgetID
            // The previous widget may have grown the panel for its own
            // content (KBO does this); reset so the new widget isn't
            // greeted with a giant blank panel. Whichever widget renders
            // next will redrive this if it cares.
            additionalExpandedHeight = 0
        }
    }

    /// Extra height a widget can request when its content needs more room
    /// than the default expanded layout. KBO uses this when a game row
    /// opens its inline box score so the panel grows instead of forcing
    /// the user to scroll the game list.
    var additionalExpandedHeight: CGFloat = 0 {
        didSet {
            guard oldValue != additionalExpandedHeight else { return }
            updatePanelDimensions()
        }
    }

    /// Which wing the cursor is over, computed by GestureHandler from
    /// the global mouse monitor. SwiftUI .onHover and NSTrackingArea
    /// don't fire reliably inside our `.nonactivatingPanel`, so wing
    /// views read this instead to flip their hover state.
    enum WingHover { case none, left, right }
    var hoveredWing: WingHover = .none

    // MARK: - Configuration

    let maxExpandedHeight: CGFloat = 260

    /// Current target height for the expanded panel — base height plus
    /// whatever extra room the active widget asked for. Used by gesture
    /// hit-testing so clicks on the dynamically-grown lower part of the
    /// panel don't read as "outside the panel" and collapse it.
    var effectiveExpandedHeight: CGFloat {
        maxExpandedHeight + additionalExpandedHeight
    }
    let wingWidth: CGFloat = 120
    var panelCornerRadius: CGFloat {
        ThemeEngine.shared.currentTheme.panelCornerRadius
    }

    // MARK: - Private

    private var hoverDebounceTask: Task<Void, Never>?
    private var collapseDelayTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    private init() {
        notchGeometry = NotchGeometry.detect()
        currentExpandedWidgetID = SettingsManager.shared.lastExpandedWidgetID ?? "music-player"
        setupScreenChangeObserver()
        updatePanelDimensions()
    }

    /// Move to the next/previous enabled widget. Wraps around at the ends.
    /// Called by the switcher bar and (eventually) keyboard arrow keys.
    func cycleWidget(direction: Int) {
        let enabled = WidgetRegistry.shared.enabledWidgets
        guard !enabled.isEmpty else { return }
        let idx = enabled.firstIndex(where: { $0.id == currentExpandedWidgetID }) ?? 0
        let next = (idx + direction + enabled.count) % enabled.count
        currentExpandedWidgetID = enabled[next].id
    }

    // MARK: - State Transitions

    /// Transition from idle → hovering (mouse enters notch proximity)
    func hover() {
        guard currentState == .idle else { return }
        hoverDebounceTask?.cancel()
        hoverDebounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            performTransition(to: .hovering)
        }
    }

    /// Transition from hovering → expanded (click on notch)
    func expand() {
        guard currentState == .hovering else { return }
        hoverDebounceTask?.cancel()
        collapseDelayTask?.cancel()
        performTransition(to: .expanded)
    }

    /// Collapse back to idle (right wing hidden)
    func collapse() {
        hoverDebounceTask?.cancel()
        collapseDelayTask?.cancel()
        performTransition(to: .idle)
    }

    /// Expand directly from any current state. Used by drag-and-drop into
    /// the notch — the user is dragging a file from cold and we want the
    /// drop zone visible without requiring a prior hover.
    func forceExpand() {
        hoverDebounceTask?.cancel()
        collapseDelayTask?.cancel()
        if currentState == .idle {
            performTransition(to: .hovering)
        }
        performTransition(to: .expanded)
    }

    /// Toggle between states
    func toggleExpand() {
        switch currentState {
        case .idle:
            hover()
        case .hovering:
            expand()
        case .expanded:
            collapse()
        }
    }

    // MARK: - Private

    private func performTransition(to newState: NotchState) {
        guard newState != currentState else { return }

        // Validate transition
        let isValid: Bool
        switch (currentState, newState) {
        case (.idle, .hovering),
             (.hovering, .expanded),
             (.hovering, .idle),
             (.expanded, .hovering),
             (.expanded, .idle):
            isValid = true
        default:
            isValid = false
        }

        guard isValid else { return }

        previousState = currentState
        currentState = newState

        // Animate panel dimensions
        updatePanelDimensions()

        // Notify EventBus
        EventBus.shared.send(.stateChanged(newState))
    }

    private func updatePanelDimensions() {
        let animation: Animation? = SettingsManager.shared.animationsEnabled ? animationForState(currentState) : nil

        withAnimation(animation) {
            // Both wings always visible
            panelWidth = notchGeometry.notchWidth + (wingWidth * 2)

            switch currentState {
            case .idle, .hovering:
                expandedHeight = 0
            case .expanded:
                expandedHeight = maxExpandedHeight + additionalExpandedHeight
            }
        }
    }

    private func animationForState(_ state: NotchState) -> Animation {
        switch state {
        case .idle: return AnimationTokens.collapse
        case .hovering: return AnimationTokens.expandHover
        case .expanded: return AnimationTokens.expandClick
        }
    }

    // MARK: - Screen Change Observer

    private func setupScreenChangeObserver() {
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.notchGeometry = NotchGeometry.detect()
                self?.updatePanelDimensions()
                EventBus.shared.send(.screenChanged)
            }
            .store(in: &cancellables)
    }
}

