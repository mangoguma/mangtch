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

// MARK: - Measured Expanded Panel Content Height PreferenceKey

/// Carries the intrinsic height of the expanded panel content from a
/// `GeometryReader` background up to `panelContent`, where it gets
/// forwarded into `BoringViewModel.measuredExpandedContentHeight`. This
/// is the source the panel `.frame(height:)` and the NSPanel resize
/// pipeline both read — replaces the formula estimate
/// (`metrics.contentHeight`) so the panel sizes to real content.
private struct ExpandedContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - ContentView

@MainActor
struct ContentView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @State private var widgetRegistry = WidgetRegistry.shared

    @State private var anyDropDebounceTask: Task<Void, Never>?

    /// Open-morph choreography: the panel shape grows alone first, then
    /// the expanded content fades in (opacity + small downward slide).
    /// Opacity-only — the content must stay mounted so the GeometryReader
    /// height measurement that drives panel sizing keeps reporting.
    @State private var expandedContentVisible = false
    @State private var contentRevealTask: Task<Void, Never>?

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
        // 7d: clamp Dynamic Type so a user with xLarge accessibility
        // settings doesn't break the notch's pixel-tuned compact wing.
        // Pixel fonts in `TypographyTokens` ignore Dynamic Type today,
        // but if a future widget uses `.body`/`.subheadline`, this cap
        // keeps the panel layout intact.
        .dynamicTypeSize(...DynamicTypeSize.large)
        .onChange(of: vm.anyDropZoneTargeting) { _, isTargeted in
            anyDropDebounceTask?.cancel()

            if isTargeted {
                // Drop escalates the panel to fully open from either
                // pre-expanded state — .hovering counts as "not yet open"
                // here, the user intent is dropping files into the shelf.
                if vm.notchState != .open {
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
        .onChange(of: vm.notchState) { _, state in
            contentRevealTask?.cancel()
            if state == .open {
                // Drag-driven opens skip the stagger — the user is holding
                // files over the shelf and needs live drop targets now, not
                // after a choreographed reveal.
                if vm.anyDropZoneTargeting || vm.dragDetectorTargeting || vm.dropEvent {
                    withAnimation(.easeOut(duration: 0.15)) {
                        expandedContentVisible = true
                    }
                    return
                }
                contentRevealTask = Task { @MainActor in
                    // 180ms ≈ the open spring's fast phase; the content
                    // arrives while the shape performs its final settle.
                    try? await Task.sleep(for: .milliseconds(180))
                    guard !Task.isCancelled, vm.notchState == .open else { return }
                    withAnimation(.contentReveal) {
                        expandedContentVisible = true
                    }
                }
            } else {
                // Exits get out of the way: content drops fast while the
                // close morph (0.30 response) is still in its first frames.
                withAnimation(.easeOut(duration: 0.10)) {
                    expandedContentVisible = false
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
                .overlay(alignment: .topLeading) { debugZonesOverlay }
            expandedContent
                // Lay the content out at the OPEN target width even while
                // closed. The measured height below is then final before
                // the morph ever starts — the height animation never
                // retargets mid-flight (formula→measured swap, or
                // width-driven re-wrap), and the content doesn't re-layout
                // on every frame of the width morph.
                .frame(width: vm.expandedTargetPanelWidth, alignment: .top)
                // Measure the **entire** expanded panel intrinsic height
                // (Divider + WidgetSwitcherBar + widget body) at the final
                // width, independent of the animated envelope below.
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: ExpandedContentHeightKey.self,
                            value: proxy.size.height
                        )
                    }
                )
                // Fade/slide only the content — the chrome (background +
                // clip shape) attaches to the animated envelope below, so
                // it grows under the morph while the content arrives
                // separately.
                .opacity(expandedContentVisible ? 1 : 0)
                .offset(y: expandedContentVisible ? 0 : -8)
                // Animated envelope: width tracks the wing morph, height
                // does the open/close reveal. The wider fixed-layout
                // content overflows it symmetrically (centered) and gets
                // clipped, so the reveal stays center-out like the wings.
                .frame(width: m.panelWidth,
                       height: vm.notchState == .open ? vm.effectiveTotalHeight : 0,
                       alignment: .top)
                .background(ThemeTokens.panelBackground(systemDark: vm.systemIsDark))
                .clipShape(
                    ExpandedPanelShape(
                        outerInset: wingTopOuterRadius,
                        bottomRadius: panelCornerRadius
                    )
                )
                .clipped()
                .onPreferenceChange(ExpandedContentHeightKey.self) { h in
                    Task { @MainActor in
                        vm.updateMeasuredExpandedContentHeight(h)
                    }
                }
                // Gate on visibility too — during the reveal delay the
                // content is transparent but already laid out, and an
                // invisible button taking a click reads as a dead panel.
                .allowsHitTesting(vm.notchState == .open && expandedContentVisible)
                .animation(vm.notchState == .open ? .openMorph : .closeMorph,
                           value: vm.notchState)
        }
        .frame(width: m.panelWidth)
        .frame(maxWidth: .infinity, alignment: .center)
        // Animate the outer panel width with the same curve the inner
        // wings use (`.frame(width: m.wingWidth) .animation(...)`). Without
        // this the outer frame snaps while wings ease — the HStack briefly
        // overflows or under-fills its container and the wings look like
        // they're "filling from the outside" instead of widening evenly.
        // Width changes while closed (track preview / hover boosts) take
        // the close spring — snappy suits those small reflows.
        .animation(vm.notchState == .open ? .openMorph : .closeMorph,
                   value: m.panelWidth)
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
                .background(ThemeTokens.wingFill(systemDark: vm.systemIsDark))
                .clipShape(
                    WingShape(
                        side: .left,
                        bottomOuterRadius: wingBottomRadius,
                        topOuterRadius: wingTopOuterRadius
                    )
                )
                .clipped()

            // Notch bar (covers the hardware notch gap)
            ThemeTokens.wingFill(systemDark: vm.systemIsDark)
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
                .background(ThemeTokens.wingFill(systemDark: vm.systemIsDark))
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
        let activeID = vm.wingOwnerID
        ZStack(alignment: .leading) {
            ForEach(widgetRegistry.widgets) { widget in
                widget.leftWingView
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .opacity(widget.id == activeID ? 1 : 0)
                    .allowsHitTesting(widget.id == activeID)
                    .environment(\.wingHitZoneEmissionEnabled,
                                 widget.id == activeID)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: activeID)
    }

    @ViewBuilder
    private var rightWingContent: some View {
        let activeID = vm.wingOwnerID
        ZStack(alignment: .trailing) {
            ForEach(widgetRegistry.widgets) { widget in
                widget.rightWingView
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .opacity(widget.id == activeID ? 1 : 0)
                    .allowsHitTesting(widget.id == activeID)
                    .environment(\.wingHitZoneEmissionEnabled,
                                 widget.id == activeID)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: activeID)
    }

    // MARK: - Expanded Content

    @ViewBuilder
    private var expandedContent: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.horizontal, LayoutTokens.dividerHorizontalInset)

            // Switcher stays centered; the hide button rides the trailing
            // edge so it never shifts the tab row as widgets come and go.
            ZStack {
                WidgetSwitcherBar(
                    widgets: widgetRegistry.enabledWidgets,
                    currentID: Binding(
                        get: { vm.currentExpandedWidgetID },
                        set: { vm.currentExpandedWidgetID = $0 }
                    )
                )
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    hideButton
                }
            }
            .padding(.horizontal, LayoutTokens.panelHorizontalInset)

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

    // MARK: - Hide Button

    /// The wings sit on top of the menu bar, so whatever menu-bar item
    /// they cover can't be clicked. This gets the whole panel out of the
    /// way; it comes back from the menu-bar icon or the global shortcut.
    @ViewBuilder
    private var hideButton: some View {
        Button {
            AppDelegate.shared?.setPanelHidden(true)
        } label: {
            Image(systemName: "eye.slash")
                .font(TypographyTokens.switcherIcon)
                .frame(width: 26, height: 22)
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Hide the panel so the menu bar is clickable")
    }

    // MARK: - Debug Zones Overlay

    /// Mirrors the four rects that `GestureHandler.handleMouseMoved`
    /// computes in screen coords — drawn here in window-local coords
    /// because the window is sized to `panelWidth × (notchHeight + …)`,
    /// so the zones map 1:1 to the wings/notch HStack origin.
    ///
    /// Zones use the same definitions as GestureHandler:
    /// - hover (yellow): full panel width × `notchH + 5 + extraOpen`
    /// - left wing (cyan): `wingW × notchH + 5`
    /// - right wing (purple): mirror of left, anchored trailing
    /// - notch (green): centered, hardware notch size
    @ViewBuilder
    private var debugZonesOverlay: some View {
        if Defaults[.debugOverlay] {
            let m = vm.metrics
            let wingW = m.wingWidth
            let notchW = vm.notchSize.width
            let notchH = vm.notchSize.height
            let panelW = m.panelWidth
            let extraOpen: CGFloat = vm.notchState == .open ? m.totalHeight : 0

            ZStack(alignment: .topLeading) {
                Rectangle()
                    .stroke(Color.yellow.opacity(0.9), lineWidth: 1)
                    .frame(width: panelW, height: notchH + 5 + extraOpen)
                Rectangle()
                    .stroke(Color.cyan.opacity(0.9), lineWidth: 1)
                    .frame(width: wingW, height: notchH + 5)
                Rectangle()
                    .stroke(Color.purple.opacity(0.9), lineWidth: 1)
                    .frame(width: wingW, height: notchH + 5)
                    .offset(x: panelW - wingW, y: 0)
                Rectangle()
                    .stroke(Color.green.opacity(0.9), lineWidth: 1)
                    .frame(width: notchW, height: notchH)
                    .offset(x: wingW, y: 0)

                // Wing-button hit zones come from PreferenceKey reports —
                // those are stored in `vm.wingHitZones` as **screen** rects.
                // Convert to window-local via the host window's frame.
                //
                // Skip in `.closed`: compact wings show title/artist text
                // (Music) or summary glyph (KBO) instead of buttons, so
                // the published button rects sit under invisible
                // `opacity:0` siblings — drawing them just clutters the
                // overlay with rects that don't correspond to anything
                // the user can click yet.
                if vm.notchState != .closed, let host = hostWindow {
                    ForEach(vm.wingHitZones, id: \.button) { z in
                        let local = NSRect(
                            x: z.rect.minX - host.frame.minX,
                            y: host.frame.maxY - z.rect.maxY,
                            width: z.rect.width,
                            height: z.rect.height
                        )
                        Rectangle()
                            .stroke(Color.orange.opacity(0.9), lineWidth: 1)
                            .frame(width: local.width, height: local.height)
                            .offset(x: local.minX, y: local.minY)
                    }
                }
            }
            .frame(width: panelW, height: notchH + 5 + extraOpen, alignment: .topLeading)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Drag Detector (retained from Phase 2 stub)

    @ViewBuilder
    var dragDetector: some View {
        // The fullscreen drop catcher only makes sense before the panel
        // is committed open — both .closed and .hovering qualify (panel is
        // still compact, so an external file drag should still register).
        if Defaults[.boringShelf] && vm.notchState != .open {
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
