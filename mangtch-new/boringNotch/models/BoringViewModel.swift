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
    /// ID of the widget currently shown in the expanded panel.
    @Published var currentExpandedWidgetID: String = "music-player"

    // MARK: - Wing/panel size
    //
    // Sizing contract: the active widget's `preferredPanelWidth` /
    // `preferredPanelHeight` are the **only** signals chrome reads. No
    // hidden measurement pass, no Combine snap. Widgets that need to
    // grow with their content (long titles, dynamic row layouts) must
    // recompute their preferred values themselves and surface them via
    // these declarations — KBOWidget is the reference pattern.

    /// Visual floor — wings need enough chrome on either side of the
    /// hardware notch to read as a connected panel rather than two
    /// disconnected pills with bare desktop showing through the gap.
    static let minWingWidth: CGFloat = LayoutTokens.minWingWidth
    /// Default panel width when no widget declares one.
    static let defaultPanelWidth: CGFloat = 480
    /// Default panel height when no widget declares one.
    static let defaultPanelHeight: CGFloat = 260
    /// Absolute safety ceiling — keeps a runaway widget from pushing
    /// the panel off-screen on small displays.
    static let absoluteMaxWingWidth: CGFloat = LayoutTokens.absoluteMaxWingWidth

    /// Wing width.
    ///
    /// - **Open** (expanded panel visible): snap to boring.notch's native
    ///   `openNotchSize.width` (640pt). The expanded views (`MusicPlayerView`,
    ///   settings, etc.) are pixel-designed against this fixed width, so any
    ///   narrower panel causes content to overflow chrome.
    /// - **Closed/hover**: honor the active widget's `preferredPanelWidth`
    ///   so compact wings size to their content (long song titles, dynamic
    ///   KBO rows). This is the Mangtch-style content-driven sizing.
    var wingWidth: CGFloat {
        if notchState == .open {
            let half = (openNotchSize.width - closedNotchSize.width) / 2
            return min(max(half, Self.minWingWidth), Self.absoluteMaxWingWidth)
        }
        let preferred = WidgetRegistry.shared
            .widget(for: currentExpandedWidgetID)?.preferredPanelWidth
            ?? Self.defaultPanelWidth
        let half = (preferred - closedNotchSize.width) / 2
        return min(max(half, Self.minWingWidth), Self.absoluteMaxWingWidth)
    }

    /// Total panel width: notch bar + both wings.
    var panelWidth: CGFloat { notchSize.width + wingWidth * 2 }

    /// Expanded panel content height.
    ///
    /// - **Open**: `openNotchSize.height` (upstream's pixel-design canvas)
    ///   + `expandedChromeTopHeight` (Divider + WidgetSwitcherBar — defined
    ///   in `sizing/matters.swift` so the NSPanel window size agrees) so
    ///   the widget content area equals the upstream-native 190pt after
    ///   the tab bar / divider eat their share.
    /// - **Closed**: honor the widget's preferred height (or default).
    ///   Currently only used by `GestureHandler` hit-zone math; harmless to
    ///   keep widget-driven here.
    var panelHeight: CGFloat {
        if notchState == .open {
            return openNotchSize.height + expandedChromeTopHeight
        }
        return WidgetRegistry.shared
            .widget(for: currentExpandedWidgetID)?.preferredPanelHeight
            ?? Self.defaultPanelHeight
    }

    /// Whether wings should render flat (no bottom radius) — true while panel is open.
    var wingsFlat: Bool { notchState == .open }

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
