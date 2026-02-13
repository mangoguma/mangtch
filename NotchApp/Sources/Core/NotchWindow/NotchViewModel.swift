import SwiftUI
import Combine

@Observable
@MainActor
final class NotchViewModel {
    // MARK: - Singleton
    static let shared = NotchViewModel()

    // MARK: - State

    private(set) var currentState: NotchState = .hovering
    private(set) var previousState: NotchState = .hovering
    private(set) var notchGeometry: NotchGeometry

    /// Current expanded panel height (animated)
    var expandedHeight: CGFloat = 0

    /// Current panel width (animated)
    var panelWidth: CGFloat = 0

    /// Whether the HUD overlay is currently visible (affects window sizing)
    var isHUDVisible: Bool = false

    // MARK: - Configuration

    let maxExpandedHeight: CGFloat = 180
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
        setupScreenChangeObserver()
        setupHUDObserver()
        updatePanelDimensions()
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

    /// Collapse back to hovering (resting state with wings visible)
    func collapse() {
        hoverDebounceTask?.cancel()
        collapseDelayTask?.cancel()
        performTransition(to: .hovering)
    }

    /// Toggle between hovering ↔ expanded
    func toggleExpand() {
        switch currentState {
        case .hovering:
            expand()
        case .expanded:
            collapse()
        default:
            break
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
            switch currentState {
            case .idle:
                expandedHeight = 0
                panelWidth = notchGeometry.notchWidth
            case .hovering:
                expandedHeight = 0
                panelWidth = notchGeometry.notchWidth + (wingWidth * 2)
            case .expanded:
                expandedHeight = maxExpandedHeight
                panelWidth = notchGeometry.notchWidth + (wingWidth * 2)
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

    // MARK: - HUD Visibility Observer

    private func setupHUDObserver() {
        EventBus.shared.hudTriggers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.isHUDVisible = true
            }
            .store(in: &cancellables)
    }

    /// Called when HUD is dismissed
    func setHUDHidden() {
        isHUDVisible = false
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

