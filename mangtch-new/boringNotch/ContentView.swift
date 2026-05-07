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

    /// Left wing: defaults to the Music album-art slot. Other widgets only
    /// take over when they have live state worth surfacing — switching the
    /// expanded panel to KBO/Timer alone does not swap the wing, which
    /// avoids the structural-AnyView flicker (each widget's `makeCompactView`
    /// returns an unrelated view tree, so SwiftUI can only crossfade or
    /// snap; the takeover gate keeps both rare).
    @ViewBuilder
    private var leftWingContent: some View {
        if vm.currentExpandedWidgetID != "music-player",
           let active = widgetRegistry.widget(for: vm.currentExpandedWidgetID),
           active.isEnabled,
           hasWingContent(active) {
            active.makeCompactView()
                .transition(.opacity)
        } else if let timerWidget = widgetRegistry.widget(for: "timer"),
                  let timer = timerWidget.wrapped as? TimerWidget,
                  timerWidget.isEnabled,
                  (timer.viewModel.isActive || timer.viewModel.displayTime > 0) {
            timerWidget.makeCompactView()
                .transition(.opacity)
        } else if let musicWidget = widgetRegistry.widget(for: "music-player"),
                  musicWidget.isEnabled {
            musicWidget.makeCompactView()
                .transition(.opacity)
        } else {
            Color.clear.frame(width: 1)
        }
    }

    /// Right wing: music info+controls by default; KBO live state when KBO is
    /// the active widget and has a live pinned game.
    @ViewBuilder
    private var rightWingContent: some View {
        if vm.currentExpandedWidgetID == "kbo",
           let kboWidget = widgetRegistry.widget(for: "kbo")?.wrapped as? KBOWidget,
           kboWidget.viewModel.selectedGame?.isLive == true {
            KBORightWingContainer(viewModel: kboWidget.viewModel)
                .transition(.opacity)
        } else {
            MusicCompactInfo()
                .transition(.opacity)
        }
    }

    /// True when a widget has live state worth claiming the wing for.
    /// Returning false keeps the wing on its Music default — the inverse
    /// of "active widget = wing widget" prevents wing identity from
    /// thrashing every time the expanded panel toggles.
    private func hasWingContent(_ widget: AnyNotchWidget) -> Bool {
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
        return true
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
