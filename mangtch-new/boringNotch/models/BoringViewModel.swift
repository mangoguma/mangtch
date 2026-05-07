//
//  BoringViewModel.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//

import Combine
import Defaults
import SwiftUI

// MARK: - Wing Hover State

enum HoveredWing: Equatable {
    case none, left, right
}

class BoringViewModel: NSObject, ObservableObject {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject var detector = FullscreenMediaDetector.shared

    let animationLibrary: BoringAnimations = .init()
    let animation: Animation?

    @Published var contentType: ContentType = .normal
    @Published private(set) var notchState: NotchState = .closed

    // MARK: - Wing hit-zone reporting (PreferenceKey output from WingHitZone modifier)
    @Published var wingHitZones: [WingHitZone] = []

    // MARK: - Wing hover state (set by GestureHandler from global mouse monitor)
    @Published var hoveredWing: HoveredWing = .none

    // MARK: - Widget layout
    //
    // Two axes — wings vs panel — driven by different sources:
    //
    // 1. `wingOwnerID` — wings only. Priority-chain driven; reflects "what
    //    is most foreground right now" (Timer running > KBO live > Music).
    //    Resolved under `withObservationTracking` by `recomputeWingOwner`,
    //    so @Observable widget state changes re-fire the resolution.
    // 2. `currentExpandedWidgetID` — expanded panel only. User-selected via
    //    `WidgetSwitcherBar`. Independent of the wing owner so a user
    //    browsing KBO standings doesn't get yanked back to Music when
    //    a different widget grabs the wings, and so the panel can host
    //    widgets that aren't currently claiming (Timer setup, KBO non-live
    //    schedule).
    //
    // Both seeded to "music-player" so chrome has a stable ID before
    // `WidgetRegistry.registerDefaults` runs.

    /// Priority-chain owner of both wings. Read-only externally.
    @Published private(set) var wingOwnerID: String = "music-player"

    /// User-selected widget shown in the expanded panel. Bound by the
    /// `WidgetSwitcherBar`; also drives `metrics` so the panel can size
    /// itself to the picked widget's `widthRange`/`heightRange`.
    @Published var currentExpandedWidgetID: String = "music-player"

    // MARK: - Wing/panel size
    //
    // Sizing contract: the active widget's `widthRange` / `heightRange`
    // declarations are the **only** signals chrome reads. Resolution lives
    // in `PanelLayoutMetrics.resolve` — pure, state-driven. Read via
    // `metrics` below.

    /// Single resolver. Widget-driven; the **source widget** depends on
    /// state because the panel and the wings can be owned by different
    /// widgets:
    ///
    /// - `.closed` → `wingOwnerID`. The wings are the only thing visible,
    ///   and their widths are computed from `panelWidth - notchWidth)/2` —
    ///   so the width must follow whatever widget is actually rendering
    ///   into the wings (priority-chain owner).
    /// - `.open` → `currentExpandedWidgetID`. The expanded panel covers
    ///   the wings; its width must fit the user-picked widget's canvas.
    @MainActor
    var metrics: PanelLayoutMetrics {
        let sourceID = notchState == .open ? currentExpandedWidgetID : wingOwnerID
        let widget = WidgetRegistry.shared.widget(for: sourceID)
        return PanelLayoutMetrics.resolve(widget: widget,
                                          notchSize: notchSize,
                                          state: notchState)
    }

    /// Mirror of `metrics` published via Combine — observers (NSPanel
    /// resize wiring in `boringNotchApp.swift`) react to changes here.
    /// Triggered by:
    ///   - @Published inputs (notchSize, notchState, currentExpandedWidgetID)
    ///     via explicit Combine subscription
    ///   - @Observable widget state (KBO games/linescore) via re-armed
    ///     `withObservationTracking` recursion
    @Published private(set) var publishedMetrics: PanelLayoutMetrics?

    /// Intrinsic content height measured by ContentView's PreferenceKey-
    /// backed GeometryReader on the expanded panel content. Drives both
    /// the inner `.frame(height:)` and NSPanel resize so the panel fits
    /// real content rather than the widget's `heightRange.ideal` estimate.
    ///
    /// `nil` until first measurement settles (typically the first SwiftUI
    /// layout pass after the panel mounts); consumers fall back to
    /// `metrics.contentHeight` for that one frame.
    @Published private(set) var measuredExpandedContentHeight: CGFloat?

    /// Total expanded panel height (Divider + WidgetSwitcherBar + widget
    /// body — i.e. everything inside `expandedContent`). The GR-backed
    /// PreferenceKey on `expandedContent` already captures the whole
    /// VStack, so this is treated as a TOTAL — no separate chrome added.
    /// Falls back to the formula estimate (`metrics.totalHeight`) before
    /// the first measurement settles.
    @MainActor
    var effectiveTotalHeight: CGFloat {
        if let m = measuredExpandedContentHeight, m > 0 { return m }
        return metrics.totalHeight
    }

    /// Called by ContentView's `onPreferenceChange` when the expanded
    /// panel's intrinsic content height changes. Filters jitter (≤0.5pt
    /// pixel-rounding ripples) to keep the NSPanel resize pipeline from
    /// thrashing.
    @MainActor
    func updateMeasuredExpandedContentHeight(_ height: CGFloat) {
        guard height > 0 else { return }
        if let current = measuredExpandedContentHeight,
           abs(current - height) < 0.5 { return }
        measuredExpandedContentHeight = height
    }

    @Published var dragDetectorTargeting: Bool = false
    @Published var generalDropTargeting: Bool = false
    @Published var dropZoneTargeting: Bool = false
    @Published var dropEvent: Bool = false
    @Published var anyDropZoneTargeting: Bool = false
    var cancellables: Set<AnyCancellable> = []
    
    @Published var hideOnClosed: Bool = true

    @Published var edgeAutoOpenActive: Bool = false
    @Published var isHoveringCalendar: Bool = false
    @Published var isBatteryPopoverActive: Bool = false

    @Published var screenUUID: String?

    @Published var notchSize: CGSize = getClosedNotchSize()
    @Published var closedNotchSize: CGSize = getClosedNotchSize()
    
    @Published var isCameraExpanded: Bool = false
    @Published var isRequestingAuthorization: Bool = false

    // MARK: - System appearance
    //
    // Tracks the system Light/Dark mode independently of SwiftUI's
    // forced `.preferredColorScheme(.dark)` on the panel — the panel's
    // text always renders dark-themed (white on dark), but the panel
    // *background shade* shifts (lighter dark in Light mode, pitch black
    // in Dark mode). Read by `ContentView` to pick `ThemeTokens.panel/wing`
    // variants.
    @Published var systemIsDark: Bool = BoringViewModel.resolveAppearance()

    /// Resolves the effective panel-shade boolean: user's `panelAppearance`
    /// override wins over the live system Light/Dark mode.
    private static func resolveAppearance() -> Bool {
        switch Defaults[.panelAppearance] {
        case .light: return false
        case .dark: return true
        case .system:
            let match = NSApp.effectiveAppearance
                .bestMatch(from: [.darkAqua, .vibrantDark, .aqua, .vibrantLight])
            return match == .darkAqua || match == .vibrantDark
        }
    }

    deinit {
        destroy()
    }

    func destroy() {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }

    init(screenUUID: String? = nil) {
        animation = animationLibrary.animation

        super.init()
        
        self.screenUUID = screenUUID
        notchSize = getClosedNotchSize(screenUUID: screenUUID)
        closedNotchSize = notchSize

        Publishers.CombineLatest3($dropZoneTargeting, $dragDetectorTargeting, $generalDropTargeting)
            .map { shelf, drag, general in
                shelf || drag || general
            }
            .assign(to: \.anyDropZoneTargeting, on: self)
            .store(in: &cancellables)

        setupDetectorObserver()
        setupMetricsTracking()
        setupWingOwnerTracking()
        setupAppearanceObserver()
    }

    private func setupAppearanceObserver() {
        // AppleInterfaceThemeChangedNotification is the documented system
        // hook for "user toggled Light/Dark in System Settings". Goes
        // through DistributedNotificationCenter (cross-process), unlike
        // the default centre.
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(appearanceDidChange),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )
        // User-facing override (`panelAppearance` in Settings) flips the
        // resolved shade independently of the system mode.
        Defaults.publisher(.panelAppearance)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.systemIsDark = BoringViewModel.resolveAppearance()
                }
            }
            .store(in: &cancellables)
    }

    @objc private func appearanceDidChange() {
        let isDark = BoringViewModel.resolveAppearance()
        Task { @MainActor [weak self] in
            self?.systemIsDark = isDark
        }
    }

    /// Wire the @Published triggers that influence `metrics`. Each emission
    /// re-runs `recomputeMetrics`, which itself re-arms a
    /// `withObservationTracking` closure so @Observable widget state changes
    /// (KBO games/linescore/starters) also re-fire it.
    private func setupMetricsTracking() {
        // `metrics` reads either `currentExpandedWidgetID` or `wingOwnerID`
        // depending on `notchState`, so both must trigger recomputation.
        let sourcesA = Publishers.CombineLatest($notchSize, $notchState)
        let sourcesB = Publishers.CombineLatest($currentExpandedWidgetID, $wingOwnerID)
        sourcesA.combineLatest(sourcesB)
            .sink { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.recomputeMetrics()
                }
            }
            .store(in: &cancellables)
    }

    /// Kicks off the priority-chain resolution loop. First evaluation
    /// runs immediately so the seeded "music-player" ID gets corrected
    /// the moment a higher-priority widget is registered and claims;
    /// subsequent re-runs are driven by `recomputeWingOwner`'s own
    /// observation tracking.
    private func setupWingOwnerTracking() {
        Task { @MainActor [weak self] in
            self?.recomputeWingOwner()
        }
    }

    @MainActor
    private func recomputeWingOwner() {
        var resolved: String!
        withObservationTracking {
            resolved = Self.resolveWingOwner()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.recomputeWingOwner()
            }
        }
        if resolved != wingOwnerID {
            wingOwnerID = resolved
        }
    }

    /// Walks the registry's enabled widgets in descending `wingPriority`
    /// order and returns the first whose `claimsWings` is true. The
    /// "music-player" ID is the floor — Music always claims, so this
    /// floor only matters during the brief window before
    /// `registerDefaults` populates the registry.
    @MainActor
    private static func resolveWingOwner() -> String {
        let candidates = WidgetRegistry.shared.enabledWidgets
            .sorted { $0.wingPriority > $1.wingPriority }
        for widget in candidates where widget.claimsWings {
            return widget.id
        }
        return "music-player"
    }

    @MainActor
    private func recomputeMetrics() {
        var resolved: PanelLayoutMetrics!
        withObservationTracking {
            resolved = self.metrics
        } onChange: { [weak self] in
            // Fired off the observation thread; bounce to main and re-arm.
            Task { @MainActor [weak self] in
                self?.recomputeMetrics()
            }
        }
        if resolved != publishedMetrics {
            publishedMetrics = resolved
        }
    }
    
    private func setupDetectorObserver() {
        // Publisher for the user’s fullscreen detection setting
        let enabledPublisher = Defaults
            .publisher(.hideNotchOption)
            .map(\.newValue)
            .map { $0 != .never }
            .removeDuplicates()

        // Publisher for the current screen UUID (non-nil, distinct)
        let screenPublisher = $screenUUID
            .compactMap { $0 }
            .removeDuplicates()

        // Publisher for fullscreen status dictionary
        let fullscreenStatusPublisher = detector.$fullscreenStatus
            .removeDuplicates()

        // Combine all three: screen UUID, fullscreen status, and enabled setting
        Publishers.CombineLatest3(screenPublisher, fullscreenStatusPublisher, enabledPublisher)
            .map { screenUUID, fullscreenStatus, enabled in
                let isFullscreen = fullscreenStatus[screenUUID] ?? false
                return enabled && isFullscreen
            }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] shouldHide in
                withAnimation(.smooth) {
                    self?.hideOnClosed = shouldHide
                }
            }
            .store(in: &cancellables)
    }

    // Computed property for effective notch height
    var effectiveClosedNotchHeight: CGFloat {
        let currentScreen = screenUUID.flatMap { NSScreen.screen(withUUID: $0) }
        let noNotchAndFullscreen = hideOnClosed && (currentScreen?.safeAreaInsets.top ?? 0 <= 0 || currentScreen == nil)
        return noNotchAndFullscreen ? 0 : closedNotchSize.height
    }

    var chinHeight: CGFloat {
        if !Defaults[.hideTitleBar] {
            return 0
        }

        guard let currentScreen = screenUUID.flatMap({ NSScreen.screen(withUUID: $0) }) else {
            return 0
        }

        if notchState == .open { return 0 }

        let menuBarHeight = currentScreen.frame.maxY - currentScreen.visibleFrame.maxY
        let currentHeight = effectiveClosedNotchHeight

        if currentHeight == 0 { return 0 }

        return max(0, menuBarHeight - currentHeight)
    }

    func isMouseHovering(position: NSPoint = NSEvent.mouseLocation) -> Bool {
        let screenFrame = getScreenFrame(screenUUID)
        if let frame = screenFrame {
            
            let baseY = frame.maxY - notchSize.height
            let baseX = frame.midX - notchSize.width / 2
            
            return position.y >= baseY && position.x >= baseX && position.x <= baseX + notchSize.width
        }
        
        return false
    }

    func open() {
        // Mangtch wing/panel layout drives expanded sizing via WidgetRegistry +
        // ContentView, not by overwriting notchSize. notchSize stays at the
        // hardware closed dimensions so wing height and GestureHandler hover
        // zones don't balloon to 640×190 and trap the panel open.
        self.notchState = .open

        // Force music information update when notch is opened
        MusicManager.shared.forceUpdate()
        // Notify widgets (e.g. KBOViewModel) that the panel opened.
        NotificationCenter.default.post(name: .boringNotchDidOpen, object: nil)
    }

    func close() {
        // Do not close while a share picker or sharing service is active
        if SharingStateManager.shared.preventNotchClose {
            return
        }
        self.notchSize = getClosedNotchSize(screenUUID: self.screenUUID)
        self.closedNotchSize = self.notchSize
        self.notchState = .closed
        self.isBatteryPopoverActive = false
        self.coordinator.sneakPeek.show = false
        self.edgeAutoOpenActive = false

        // Set the current view to shelf if it contains files and the user enables openShelfByDefault
        // Otherwise, if the user has not enabled openLastShelfByDefault, set the view to home
    if !ShelfStateViewModel.shared.isEmpty && Defaults[.openShelfByDefault] {
            coordinator.currentView = .shelf
        } else if !coordinator.openLastTabByDefault {
            coordinator.currentView = .home
        }
    }

    func closeHello() {
        Task { @MainActor in
            withAnimation(animationLibrary.animation) {
                coordinator.helloAnimationRunning = false
                close()
            }
        }
    }
}
