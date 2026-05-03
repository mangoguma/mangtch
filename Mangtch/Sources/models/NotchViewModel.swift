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
            // Wing/panel widths depend on the active widget's preferred
            // panel width — re-snap them now that the active widget has
            // changed. (didSet on additionalExpandedHeight only updates
            // when the value itself changes, which it might not have.)
            updatePanelDimensions()
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
    /// Floor width — the wings need enough chrome on either side of the
    /// hardware notch to read as a connected panel rather than two
    /// disconnected pills with an awkward gap of bare desktop showing
    /// through where the notch sits. 130pt was tuned visually.
    static let minWingWidth: CGFloat = 130
    /// Ceiling width — keeps a runaway long string (long songs, long
    /// player names) from pushing the panel off the side of the screen.
    static let maxWingWidth: CGFloat = 260

    /// Default panel width when no widget declares one (or none is
    /// active yet). Wide enough for music + most secondary widgets;
    /// widgets with content-heavier expanded views can override via
    /// `NotchWidget.preferredPanelWidth`.
    static let defaultPanelWidth: CGFloat = 480

    /// Wing width to actually render with. Stored (not computed) so that
    /// `withAnimation` blocks in transition methods can interpolate it
    /// smoothly. Recomputed via `targetWingWidth()` whenever inputs
    /// change (state, active widget, preview).
    var wingWidth: CGFloat = 120

    /// Width to render the wing at while a freshly-started track is being
    /// previewed (~1.5s after the track changes). `nil` means no preview;
    /// a value temporarily replaces `panelModeWingWidth`. Caller (the
    /// music view model) sizes this to the actual title text width so
    /// the wing fits the new track exactly, no more no less.
    var previewWingWidth: CGFloat? = nil {
        didSet {
            guard oldValue != previewWingWidth else { return }
            snapWingWidth()
        }
    }

    /// What `wingWidth` should be right now. Both compact and panel modes
    /// pull from a single source so a hover-to-expand never causes a
    /// width snap. A non-nil `previewWingWidth` temporarily overrides
    /// the resting width but is clamped so it can never shrink below
    /// the panel-derived resting width or grow past `maxWingWidth`.
    private func targetWingWidth() -> CGFloat {
        let resting = panelModeWingWidth
        guard let preview = previewWingWidth else { return resting }
        return min(max(preview, resting), Self.maxWingWidth)
    }

    /// Re-run `targetWingWidth()` and propagate to `wingWidth`/`panelWidth`.
    /// No animation — the track-change preview snaps the wing to the new
    /// title's width and back. Animating the width change felt mechanical
    /// at any tempo we tried (fast = snappy, slow = laggy); a clean cut
    /// reads as "the new track replaced the old" rather than chrome
    /// pulsing for attention.
    private func snapWingWidth() {
        wingWidth = targetWingWidth()
        panelWidth = notchGeometry.notchWidth + (wingWidth * 2)
    }

    /// True when wings should render in their flat, panel-continuous
    /// form (square corners, panel-mode width). Sequenced separately
    /// from `expandedHeight` so the corner/width snap leads on expand
    /// and lags on collapse, instead of interpolating in lockstep with
    /// the panel growing/shrinking. Driven by `performTransition`.
    var wingsFlat: Bool = false

    /// Convenience alias — kept for any callers that read it. The wing
    /// width selector now follows `wingsFlat` directly so the corner
    /// snap and the width snap share one source of truth.
    var isPanelMode: Bool { wingsFlat }

    /// Half of the active widget's preferred panel width minus the
    /// hardware notch. Falls back to a sensible default when no widget
    /// is registered or the active one doesn't declare a width.
    private var panelModeWingWidth: CGFloat {
        let preferred = WidgetRegistry.shared
            .widget(for: currentExpandedWidgetID)?
            .preferredPanelWidth ?? Self.defaultPanelWidth
        let half = (preferred - notchGeometry.notchWidth) / 2
        return min(max(half, Self.minWingWidth), Self.maxWingWidth)
    }

    /// Hit zones for clickable wing buttons, in screen coordinates.
    /// Updated by NotchContentView's PreferenceKey aggregation; consumed
    /// by GestureHandler's manual click dispatch (the panel is
    /// `.nonactivatingPanel`, so SwiftUI's own gestures don't fire here).
    var wingHitZones: [WingHitZone] = []
    var panelCornerRadius: CGFloat {
        ThemeManager.shared.currentTheme.panelCornerRadius
    }

    // MARK: - Private

    private var hoverDebounceTask: Task<Void, Never>?
    private var collapseDelayTask: Task<Void, Never>?
    private var phaseTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    /// One unified tempo for every notch animation. Wing snap, panel
    /// height, wait between phases, and widget-swap width-changes all
    /// derive from this so the user perceives a single cadence rather
    /// than four animations running at four different speeds.
    private static let baseAnimationDuration: Double = 0.22
    /// Wing flat/round snap matches the base tempo.
    private static let wingSnapDuration: Double = baseAnimationDuration
    /// Panel grow/shrink matches the base tempo (and is the wait time
    /// before the trailing wing snap fires on collapse).
    private static let panelTransitionDuration: Double = baseAnimationDuration

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
        autoSelectWidgetForExpand()
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
        autoSelectWidgetForExpand()
        if currentState == .idle {
            performTransition(to: .hovering)
        }
        performTransition(to: .expanded)
    }

    /// Pick the widget the panel should open to based on what's actively
    /// surfacing in the wings. KBO claiming the wing while a game is
    /// live should also claim the panel; otherwise fall back to music
    /// when there's a track. Without this, users had to manually click
    /// the music or baseball tab even though the wing already reflected
    /// what they were paying attention to.
    private func autoSelectWidgetForExpand() {
        let registry = WidgetRegistry.shared

        if let kbo = registry.widget(for: "kbo")?.wrapped as? KBOWidget,
           registry.widget(for: "kbo")?.isEnabled == true,
           kbo.viewModel.selectedGame?.isLive == true {
            if currentExpandedWidgetID != "kbo" {
                currentExpandedWidgetID = "kbo"
            }
            return
        }

        if let music = registry.widget(for: "music-player")?.wrapped as? MusicPlayerWidget,
           registry.widget(for: "music-player")?.isEnabled == true,
           music.viewModel.nowPlaying != nil {
            if currentExpandedWidgetID != "music-player" {
                currentExpandedWidgetID = "music-player"
            }
        }
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

        let wasExpanded = currentState == .expanded
        let willBeExpanded = newState == .expanded

        previousState = currentState
        currentState = newState

        // Cancel any in-flight phase sequencing — re-driving the
        // transition from a fresh state below.
        phaseTask?.cancel()

        if !wasExpanded && willBeExpanded {
            // EXPAND: wings flatten/widen first, then panel grows.
            phaseTask = Task { @MainActor in
                snapWingsFlat(true)
                try? await Task.sleep(for: .milliseconds(Int(Self.wingSnapDuration * 1000)))
                guard !Task.isCancelled, currentState == .expanded else { return }
                animatePanelHeight()
            }
        } else if wasExpanded && !willBeExpanded {
            // COLLAPSE: panel shrinks first, then wings round/narrow back.
            animatePanelHeight()
            phaseTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(Int(Self.panelTransitionDuration * 1000)))
                guard !Task.isCancelled, currentState != .expanded else { return }
                snapWingsFlat(false)
            }
        } else {
            // Idle ↔ hovering — no panel involvement, just keep wings
            // round and let any height that's somehow still up settle.
            animatePanelHeight()
            snapWingsFlat(false)
        }

        EventBus.shared.send(.stateChanged(newState))
    }

    /// Toggle the wing flat-vs-rounded look + width with a fast snap.
    /// Width updates inside the same animation so corner radius and
    /// chrome width stay in lockstep.
    private func snapWingsFlat(_ flat: Bool) {
        let animation: Animation? = SettingsManager.shared.animationsEnabled
            ? .easeInOut(duration: Self.wingSnapDuration)
            : nil
        withAnimation(animation) {
            wingsFlat = flat
            wingWidth = targetWingWidth()
            panelWidth = notchGeometry.notchWidth + (wingWidth * 2)
        }
    }

    /// Animate `expandedHeight` to whatever the current state demands.
    /// Uses the same easeInOut tempo as every other notch animation so
    /// wing snap, panel height, and widget-swap width all share one
    /// rhythm. (The springy `panelSpring` token stayed inconsistent with
    /// the eased wing snap and made the sequence feel unsynced.)
    private func animatePanelHeight() {
        let animation: Animation? = SettingsManager.shared.animationsEnabled
            ? .easeInOut(duration: Self.panelTransitionDuration)
            : nil
        withAnimation(animation) {
            switch currentState {
            case .idle, .hovering:
                expandedHeight = 0
            case .expanded:
                expandedHeight = maxExpandedHeight + additionalExpandedHeight
            }
        }
    }

    /// External callers (additionalExpandedHeight didSet, widget swap,
    /// screen change) that need to re-run the layout pipeline without
    /// going through a full state transition. Snaps both height and
    /// width together — phasing only matters around state edges.
    private func updatePanelDimensions() {
        let animation: Animation? = SettingsManager.shared.animationsEnabled
            ? .easeInOut(duration: 0.22)
            : nil
        withAnimation(animation) {
            switch currentState {
            case .idle, .hovering:
                expandedHeight = 0
            case .expanded:
                expandedHeight = maxExpandedHeight + additionalExpandedHeight
            }
            wingWidth = targetWingWidth()
            panelWidth = notchGeometry.notchWidth + (wingWidth * 2)
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

