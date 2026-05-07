//
//  ContentView.swift
//  boringNotchApp
//
//  Phase 3: Mangtch-style wings + WidgetSwitcherBar layout.
//  No KBO/Timer/Music widget features yet — Phase 4 ports those.
//

import Defaults
import SwiftUI

// MARK: - Measured Wing Width PreferenceKey

/// Reports the natural width of wing content for auto-sizing.
// MARK: - ContentView

@MainActor
struct ContentView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @State private var widgetRegistry = WidgetRegistry.shared

    @State private var anyDropDebounceTask: Task<Void, Never>?

    /// The host window — injected by AppDelegate so WingHitZone can convert
    /// SwiftUI-global rects to screen coordinates from *this* window.
    var hostWindow: NSWindow? = nil

    // MARK: - Panel corner radius (matches boring.notch defaults)
    private let panelCornerRadius: CGFloat = LayoutTokens.panelCornerRadius

    // MARK: - Outer boring-notch concave radius
    private var wingTopOuterRadius: CGFloat { vm.metrics.wingWidth > 0 ? LayoutTokens.wingTopOuterRadius : 0 }

    var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .top) {
                panelContent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .panGesture(direction: .down) { _, phase in
                guard phase == .began, vm.notchState != .open else { return }
                vm.open()
            }
            .panGesture(direction: .up) { _, phase in
                guard phase == .began, vm.notchState == .open else { return }
                vm.close()
            }
        }
        .ignoresSafeArea()
        .environment(\.notchHostWindow, hostWindow)
        .background(dragDetector)
        .preferredColorScheme(.dark)
        .onChange(of: vm.anyDropZoneTargeting) { _, isTargeted in
            anyDropDebounceTask?.cancel()

            if isTargeted {
                if vm.notchState == .closed {
                    coordinator.currentView = .shelf
                    vm.open()
                }
                return
            }

            anyDropDebounceTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }

                if vm.dropEvent {
                    vm.dropEvent = false
                    return
                }

                vm.dropEvent = false
                if !SharingStateManager.shared.preventNotchClose {
                    vm.close()
                }
            }
        }
    }

    // MARK: - Panel Content

    @ViewBuilder
    private var panelContent: some View {
        let m = vm.metrics
        VStack(spacing: 0) {
            wingsRow
            expandedContent
                .frame(width: m.panelWidth, alignment: .top)
                .background(Color(white: 0.14))
                .clipShape(
                    ExpandedPanelShape(
                        outerInset: wingTopOuterRadius,
                        bottomRadius: panelCornerRadius
                    )
                )
                .frame(height: vm.notchState == .open ? m.totalHeight : 0, alignment: .top)
                .clipped()
                .allowsHitTesting(vm.notchState == .open)
                .animation(.easeInOut(duration: 0.22), value: vm.notchState)
        }
        .frame(width: m.panelWidth)
        .frame(maxWidth: .infinity, alignment: .center)
        // Animate the outer panel width with the same curve the inner
        // wings use (`.frame(width: m.wingWidth) .animation(...)`). Without
        // this the outer frame snaps while wings ease — the HStack briefly
        // overflows or under-fills its container and the wings look like
        // they're "filling from the outside" instead of widening evenly.
        .animation(.easeInOut(duration: 0.22), value: m.panelWidth)
    }

    // MARK: - Wings Row

    @ViewBuilder
    private var wingsRow: some View {
        let m = vm.metrics
        let wingsFlat = vm.notchState == .open
        let wingBottomRadius: CGFloat = wingsFlat ? 0 : panelCornerRadius
        let wingTopOuterRadius = self.wingTopOuterRadius

        HStack(spacing: 0) {
            // Left wing
            leftWingContent
                .padding(.leading, wingTopOuterRadius)
                .environment(\.colorScheme, .dark)
                .frame(width: m.wingWidth, height: vm.notchSize.height,
                       alignment: .leading)
                .background(Color.black)
                .clipShape(
                    WingShape(
                        side: .left,
                        bottomOuterRadius: wingBottomRadius,
                        topOuterRadius: wingTopOuterRadius
                    )
                )
                .clipped()

            // Notch bar (covers the hardware notch gap)
            Color.black
                .frame(width: vm.notchSize.width + 2,
                       height: vm.notchSize.height)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: m.wingWidth > 0 ? 0 : panelCornerRadius,
                        bottomTrailingRadius: m.wingWidth > 0 ? 0 : panelCornerRadius,
                        topTrailingRadius: 0
                    )
                )
                .padding(.horizontal, -1)

            // Right wing
            rightWingContent
                .padding(.trailing, wingTopOuterRadius)
                .environment(\.colorScheme, .dark)
                .frame(width: m.wingWidth, height: vm.notchSize.height,
                       alignment: .trailing)
                .background(Color.black)
                .clipShape(
                    WingShape(
                        side: .right,
                        bottomOuterRadius: wingBottomRadius,
                        topOuterRadius: wingTopOuterRadius
                    )
                )
                .clipped()
        }
        // Collect wing hit zones reported by child views.
        .onPreferenceChange(WingHitZonesKey.self) { zones in
            var seen: [WingButton: WingHitZone] = [:]
            for z in zones { seen[z.button] = z }
            vm.wingHitZones = Array(seen.values)
        }
    }

    // MARK: - Wing Contents
    //
    // Both wings stable-mount every widget's wing tree (left and right)
    // in a ZStack and toggle visibility per active owner via opacity +
    // hit-zone emission gating. Trees keep SwiftUI view identity for the
    // app's lifetime, so swapping owners no longer remounts subtrees,
    // resets internal state, or churns hit-zone preferences. The earlier
    // `if/else AnyView` chain made SwiftUI's diff non-deterministic
    // (sometimes crossfade, sometimes snap) and produced the wing flicker
    // the panel never had — the panel always rendered identity-stable
    // single-child branches via `.id(widget.id) .transition(.opacity)`.

    @ViewBuilder
    private var leftWingContent: some View {
        let activeID = leftWingOwnerID
        ZStack(alignment: .leading) {
            ForEach(widgetRegistry.widgets) { widget in
                if let tree = widget.leftWingView {
                    tree
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .opacity(widget.id == activeID ? 1 : 0)
                        .allowsHitTesting(widget.id == activeID)
                        .environment(\.wingHitZoneEmissionEnabled,
                                     widget.id == activeID)
                }
            }
        }
        .animation(.easeInOut(duration: 0.22), value: activeID)
    }

    @ViewBuilder
    private var rightWingContent: some View {
        let activeID = rightWingOwnerID
        ZStack(alignment: .trailing) {
            ForEach(widgetRegistry.widgets) { widget in
                if let tree = widget.rightWingView {
                    tree
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                        .opacity(widget.id == activeID ? 1 : 0)
                        .allowsHitTesting(widget.id == activeID)
                        .environment(\.wingHitZoneEmissionEnabled,
                                     widget.id == activeID)
                }
            }
        }
        .animation(.easeInOut(duration: 0.22), value: activeID)
    }

    // MARK: - Wing Owner Resolution
    //
    // Single source of truth for which mounted wing tree should be visible
    // and emit hit zones. Trees themselves are stable-mounted regardless;
    // these resolvers only decide opacity/emission.

    /// Left-wing precedence: active expanded widget claims iff it has
    /// live content → Timer iff running → Music default. Mirrors the
    /// pre-refactor `hasWingContent` policy.
    private var leftWingOwnerID: String {
        if vm.currentExpandedWidgetID != "music-player",
           let active = widgetRegistry.widget(for: vm.currentExpandedWidgetID),
           active.isEnabled,
           widgetClaimsLeftWing(active) {
            return active.id
        }
        if let timerWidget = widgetRegistry.widget(for: "timer"),
           let timer = timerWidget.wrapped as? TimerWidget,
           timerWidget.isEnabled,
           timer.viewModel.isActive || timer.viewModel.displayTime > 0 {
            return "timer"
        }
        return "music-player"
    }

    /// Right-wing precedence: KBO live game when KBO panel is active →
    /// Music default otherwise.
    private var rightWingOwnerID: String {
        if vm.currentExpandedWidgetID == "kbo",
           let kboWidget = widgetRegistry.widget(for: "kbo"),
           kboWidget.isEnabled,
           let kbo = kboWidget.wrapped as? KBOWidget,
           kbo.viewModel.selectedGame?.isLive == true {
            return "kbo"
        }
        return "music-player"
    }

    private func widgetClaimsLeftWing(_ widget: AnyNotchWidget) -> Bool {
        if let timer = widget.wrapped as? TimerWidget {
            return timer.viewModel.isActive || timer.viewModel.displayTime > 0
        }
        if let kbo = widget.wrapped as? KBOWidget {
            // Hold the wing while the user is browsing a non-today date —
            // they're clearly in the KBO context and flipping wings to
            // music under a KBO panel is jarring. Otherwise only claim
            // for a pinned live game.
            if !kbo.viewModel.isShowingToday { return true }
            return kbo.viewModel.selectedGame?.isLive == true
        }
        return widget.leftWingView != nil
    }

    // MARK: - Expanded Content

    @ViewBuilder
    private var expandedContent: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.horizontal, LayoutTokens.dividerHorizontalInset)

            WidgetSwitcherBar(
                widgets: widgetRegistry.enabledWidgets,
                currentID: Binding(
                    get: { vm.currentExpandedWidgetID },
                    set: { vm.currentExpandedWidgetID = $0 }
                )
            )

            Group {
                if let widget = widgetRegistry.widget(for: vm.currentExpandedWidgetID),
                   widget.isEnabled {
                    widget.makeExpandedView()
                        .id(widget.id)
                        .transition(.opacity)
                } else if let first = widgetRegistry.enabledWidgets.first {
                    first.makeExpandedView()
                        .id(first.id)
                        .transition(.opacity)
                        .onAppear { vm.currentExpandedWidgetID = first.id }
                } else {
                    Text("No widgets enabled")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 100)
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
            // Inset content from the panel chrome — boring.notch original
            // does the same (`ContentView.swift:102` in the upstream repo).
            // Without this the widget view extends to `panelWidth` and gets
            // clipped by `ExpandedPanelShape`'s outer inset + bottom radius.
            .padding(.horizontal, LayoutTokens.panelHorizontalInset)
            .padding(.bottom, LayoutTokens.panelBottomInset)
        }
    }

    // MARK: - Drag Detector (retained from Phase 2 stub)

    @ViewBuilder
    var dragDetector: some View {
        if Defaults[.boringShelf] && vm.notchState == .closed {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data],
                        isTargeted: $vm.dragDetectorTargeting) { providers in
                    vm.dropEvent = true
                    ShelfStateViewModel.shared.load(providers)
                    return true
                }
        } else {
            EmptyView()
        }
    }
}

// MARK: - Drop Delegates (retained from stub for ShelfView compatibility)

struct FullScreenDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    let onDrop: () -> Void

    func dropEntered(info _: DropInfo) { isTargeted = true }
    func dropExited(info _: DropInfo) { isTargeted = false }
    func performDrop(info _: DropInfo) -> Bool { isTargeted = false; onDrop(); return true }
}

struct GeneralDropTargetDelegate: DropDelegate {
    @Binding var isTargeted: Bool

    func dropEntered(info: DropInfo) { isTargeted = true }
    func dropExited(info: DropInfo) { isTargeted = false }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .cancel) }
    func performDrop(info: DropInfo) -> Bool { false }
}
