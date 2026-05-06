import SwiftUI
import Defaults

@Observable
@MainActor
final class NotchViewModel {
    // MARK: - Primary instance accessor
    /// Returns the panel attached to the resolver-chosen "primary"
    /// display. External callsites (music VM, KBO, shortcuts, drag
    /// detector) target the primary so behaviour is unchanged on
    /// single-display setups; the manager owns secondary instances when
    /// `showOnAllDisplays` is on.
    static var shared: NotchViewModel { NotchWindowManager.shared.primaryViewModel }

    // MARK: - State

    /// Refresh the cached `NSScreen` reference. AppKit replaces NSScreen
    /// instances when displays reconfigure (resolution change, sleep,
    /// hot-plug), so the original `let`-bound reference can report a
    /// stale `frame` — which fed back into NotchGeometry detection,
    /// pushing the geometry of one display onto another window.
    @MainActor
    func rebind(to screen: NSScreen) {
        guard self.screen !== screen else { return }
        self.screen = screen
        self.notchGeometry = NotchGeometry.detect(for: screen)
        updatePanelDimensions()
        EventBus.shared.send(.screenChanged)
    }

    /// The screen this view model is attached to. Each `NotchWindow`
    /// owns one VM matched to its display.
    private(set) var screen: NSScreen

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

    /// Measured natural width of wing compact content. Updated by
    /// NotchContentView's hidden measurement overlay. Used to size
    /// wings to fit their content in idle/hovering state.
    var measuredCompactWidth: CGFloat = 0 {
        didSet {
            guard oldValue != measuredCompactWidth, currentState != .expanded else { return }
            updatePanelDimensions()
        }
    }

    // MARK: - Debug
    var debugHoverElapsed: Double = 0
    var debugHoverDuration: Double = 0

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
    /// Instance-stored so `WidgetRegistry.recomputeMaxWingWidth()` can
    /// derive it from the widest registered widget instead of a literal
    /// that drifts every time a widget grows. Hard ceiling: 480.
    var maxWingWidth: CGFloat = 240

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

    /// True when at least one widget has content worth surfacing in the
    /// wings. When false the wings collapse to zero width so the notch
    /// bar blends with the hardware bezel.
    var hasWingContent: Bool {
        // Expanded — always show wings so the panel chrome is consistent.
        if currentState == .expanded { return true }

        // User explicitly selected a non-music widget — always show wings.
        if currentExpandedWidgetID != "music-player",
           let widget = WidgetRegistry.shared.widget(for: currentExpandedWidgetID),
           widget.isEnabled {
            return true
        }

        // Any non-music widget claiming the wing via fallback?
        let widgetID = effectiveWingWidgetID(fallback: currentExpandedWidgetID)
        if widgetID != "music-player" { return true }

        return hasMusicTrack
    }

    /// True when the right wing has content to display. The right wing
    /// shows KBO info or music track info — when neither is available
    /// it collapses to 0 width while the left wing stays visible.
    var hasRightWingContent: Bool {
        if currentState == .expanded { return true }

        let selectedID = currentExpandedWidgetID
        if selectedID == "kbo",
           let kboWidget = WidgetRegistry.shared.widget(for: "kbo"),
           kboWidget.isEnabled {
            if let kbo = kboWidget.wrapped as? KBOWidget {
                if !kbo.viewModel.isShowingToday { return true }
                return kbo.viewModel.selectedGame?.isLive == true
            }
        }
        return hasMusicTrack
    }

    /// Helper: true when music is playing or a track is loaded.
    private var hasMusicTrack: Bool {
        guard let musicWidget = WidgetRegistry.shared.widget(for: "music-player"),
              let music = musicWidget.wrapped as? MusicPlayerWidget,
              musicWidget.isEnabled else { return false }
        return music.viewModel.nowPlaying != nil
            && !(music.viewModel.nowPlaying?.title.isEmpty ?? true)
    }

    /// What `wingWidth` should be right now.
    /// - Expanded: panel-derived width (from widget's preferredPanelWidth)
    /// - Idle/hovering: measured compact content width (auto-fit)
    /// - Track-change preview: temporarily boosted to title width
    private func targetWingWidth() -> CGFloat {
        if !hasWingContent { return 0 }

        if currentState == .expanded {
            // At least as wide as the compact content so wings never
            // shrink on expand.
            let compact = measuredCompactWidth + 4
            let resting = max(panelModeWingWidth, compact)
            guard let preview = previewWingWidth else { return min(resting, self.maxWingWidth) }
            return min(max(preview, resting), self.maxWingWidth)
        }

        // Idle/hovering: use measured content width + small padding
        let measured = measuredCompactWidth + 4
        let clamped = min(max(measured, 50), self.maxWingWidth)

        // Track-change preview can still boost
        guard let preview = previewWingWidth else { return clamped }
        return min(max(preview, clamped), self.maxWingWidth)
    }

    /// Re-run `targetWingWidth()` and propagate to `wingWidth`/`panelWidth`.
    /// No animation — the track-change preview snaps the wing to the new
    /// title's width and back. Animating the width change felt mechanical
    /// at any tempo we tried (fast = snappy, slow = laggy); a clean cut
    /// reads as "the new track replaced the old" rather than chrome
    /// pulsing for attention.
    private func snapWingWidth() {
        wingWidth = targetWingWidth()
        panelWidth = computePanelWidth()
    }

    /// Compute total panel width. Always symmetric (both wings) so the
    /// window stays centered on the hardware notch.
    private func computePanelWidth() -> CGFloat {
        return notchGeometry.notchWidth + wingWidth * 2
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
    ///
    /// When the panel is closed, the wing width follows whichever widget
    /// is *actually* on the wing — not the last panel-selected one. KBO
    /// without a pinned live game falls back to music in `hasContentToShow`,
    /// so the width must follow that fallback too; otherwise peeking at
    /// the KBO panel and closing without pinning leaves the wing
    /// permanently wider than the music it's now displaying.
    private var panelModeWingWidth: CGFloat {
        let registry = WidgetRegistry.shared
        let activeID: String
        if currentState == .expanded {
            activeID = currentExpandedWidgetID
        } else {
            activeID = effectiveWingWidgetID(fallback: currentExpandedWidgetID)
        }
        let preferred = registry.widget(for: activeID)?.preferredPanelWidth
            ?? Self.defaultPanelWidth
        let half = (preferred - notchGeometry.notchWidth) / 2
        return min(max(half, Self.minWingWidth), self.maxWingWidth)
    }

    /// Mirrors `NotchContentView.hasContentToShow`: when the panel-selected
    /// widget has nothing live worth surfacing on the wing, the wings
    /// render music as a fallback — so the *width* should follow music too.
    private func effectiveWingWidgetID(fallback: String) -> String {
        let registry = WidgetRegistry.shared
        guard let active = registry.widget(for: fallback), active.isEnabled else {
            return activeTimerOrMusic()
        }
        if let kbo = active.wrapped as? KBOWidget {
            let claimsWing = !kbo.viewModel.isShowingToday
                || kbo.viewModel.selectedGame?.isLive == true
            return claimsWing ? fallback : activeTimerOrMusic()
        }
        if let fs = active.wrapped as? FileShelfWidget {
            return fs.viewModel.items.isEmpty ? activeTimerOrMusic() : fallback
        }
        if let timer = active.wrapped as? TimerWidget {
            let claimsWing = timer.viewModel.displayTime > 0 || timer.viewModel.isActive
            return claimsWing ? fallback : "music-player"
        }
        return fallback
    }

    /// Fallback: active timer if running, otherwise music.
    private func activeTimerOrMusic() -> String {
        if let timerWidget = WidgetRegistry.shared.widget(for: "timer"),
           let timer = timerWidget.wrapped as? TimerWidget,
           timerWidget.isEnabled,
           (timer.viewModel.isActive || timer.viewModel.displayTime > 0) {
            return "timer"
        }
        return "music-player"
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

    init(screen: NSScreen) {
        self.screen = screen
        self.notchGeometry = NotchGeometry.detect(for: screen)
        self.currentExpandedWidgetID = SettingsManager.shared.lastExpandedWidgetID ?? "music-player"
        updatePanelDimensions()
        setupWidgetWidthObserver()
    }

    /// Re-detect notch geometry from the current `screen`. Called by the
    /// owning `NotchWindow` when display parameters change. Keeps the
    /// per-instance geometry in sync with the actual hardware so multiple
    /// VMs (one per display) don't all read primary-screen dimensions.
    func refreshGeometry() {
        notchGeometry = NotchGeometry.detect(for: screen)
        updatePanelDimensions()
    }

    /// Re-snap wing width after the music playing state changes.
    func refreshWingVisibility() {
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
            // Re-check current cursor position so the expand timer starts
            // immediately if the cursor already reached the notch zone
            // while the debounce was in flight.
            GestureHandler.shared.recheckCurrentPosition()
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

    /// Ensure the selected widget is still valid. Only auto-select when
    /// the current selection is disabled or missing — otherwise respect
    /// the user's last explicit choice (persisted in Defaults).
    private func autoSelectWidgetForExpand() {
        let registry = WidgetRegistry.shared

        // If the persisted widget is still enabled, keep it.
        if let current = registry.widget(for: currentExpandedWidgetID),
           current.isEnabled {
            return
        }

        // Fallback: pick the first enabled widget.
        if let first = registry.enabledWidgets.first {
            currentExpandedWidgetID = first.id
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
            // EXPAND: flatten corners instantly, then animate panel growth.
            // Corners must be square BEFORE the panel starts growing,
            // otherwise the rounded gap is visible during the animation.
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                wingsFlat = true
                wingWidth = targetWingWidth()
                panelWidth = computePanelWidth()
            }
            let anim: Animation? = SettingsManager.shared.animationsEnabled
                ? .easeInOut(duration: Self.panelTransitionDuration)
                : nil
            withAnimation(anim) {
                expandedHeight = maxExpandedHeight + additionalExpandedHeight
            }
        } else if wasExpanded && !willBeExpanded {
            let willHideWings = !hasWingContent
            let anim: Animation? = SettingsManager.shared.animationsEnabled
                ? .easeInOut(duration: Self.panelTransitionDuration)
                : nil

            if willHideWings {
                // No wing content — shrink panel first, then snap wings away.
                withAnimation(anim) {
                    expandedHeight = 0
                }
                phaseTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(Int(Self.panelTransitionDuration * 1000)))
                    guard !Task.isCancelled else { return }
                    var t = Transaction()
                    t.disablesAnimations = true
                    withTransaction(t) {
                        wingsFlat = false
                        wingWidth = targetWingWidth()
                        panelWidth = computePanelWidth()
                    }
                }
            } else {
                // Wing content stays — shrink panel + round corners together.
                withAnimation(anim) {
                    expandedHeight = 0
                }
                // Round corners after panel is gone
                phaseTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(Int(Self.panelTransitionDuration * 1000)))
                    guard !Task.isCancelled else { return }
                    let snapAnim: Animation? = SettingsManager.shared.animationsEnabled
                        ? .easeInOut(duration: Self.wingSnapDuration)
                        : nil
                    withAnimation(snapAnim) {
                        wingsFlat = false
                        wingWidth = targetWingWidth()
                        panelWidth = computePanelWidth()
                    }
                }
            }
        } else {
            // Idle ↔ hovering — just update dimensions, no panel.
            let anim: Animation? = SettingsManager.shared.animationsEnabled
                ? .easeInOut(duration: Self.wingSnapDuration)
                : nil
            withAnimation(anim) {
                wingWidth = targetWingWidth()
                panelWidth = computePanelWidth()
                expandedHeight = 0
            }
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
            panelWidth = computePanelWidth()
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
    /// going through a full state transition.
    func updatePanelDimensions() {
        let signpostState = dimensionsSignposter.beginInterval("updatePanelDimensions")
        defer { dimensionsSignposter.endInterval("updatePanelDimensions", signpostState) }

        let prevPanel = panelWidth
        let prevWing = wingWidth
        let newWing = targetWingWidth()
        let growing = newWing > wingWidth

        if growing {
            // Wing is getting wider — snap width instantly so the panel
            // background fills the new space before SwiftUI renders.
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                wingWidth = newWing
                panelWidth = computePanelWidth()
            }
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
            }
        } else {
            // Wing is shrinking or unchanged — animate everything together.
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
                wingWidth = newWing
                panelWidth = computePanelWidth()
            }
        }
        dimensionsLog.debug("panel \(prevPanel)→\(self.panelWidth) wing \(prevWing)→\(self.wingWidth) widget=\(self.currentExpandedWidgetID)")
    }

    // MARK: - Widget Width Observer

    private func setupWidgetWidthObserver() {
        withObservationTracking {
            let registry = WidgetRegistry.shared
            let wingID = effectiveWingWidgetID(fallback: currentExpandedWidgetID)
            _ = registry.widget(for: currentExpandedWidgetID)?.preferredPanelWidth
            _ = registry.widget(for: wingID)?.preferredPanelWidth
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.setupWidgetWidthObserver()
                self?.updatePanelDimensions()
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

}

