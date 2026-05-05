import SwiftUI
import Defaults

struct NotchContentView: View {
    /// The per-window view model. Each `NotchWindow` constructs its own
    /// content view with its own VM so multi-display fan-out gives every
    /// panel independent hover/expand state.
    @State private var viewModel: NotchViewModel
    /// The host panel — needed by `WingHitZone` to convert SwiftUI-global
    /// rects to screen coordinates from *this* window, not whatever the
    /// `NotchWindow.shared` accessor happens to resolve to.
    private let hostWindow: NotchWindow
    @State private var widgetRegistry = WidgetRegistry.shared
    @State private var settings = SettingsManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared

    init(viewModel: NotchViewModel, hostWindow: NotchWindow) {
        self._viewModel = State(initialValue: viewModel)
        self.hostWindow = hostWindow
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                panelContent(in: geo)

                // Debug zone visualization (toggle in Settings > Widgets)
                if Defaults[.debugOverlay] {
                    debugZoneOverlay(in: geo)
                }

                // HUD overlay (shows on top of everything)
                hudOverlay

                // Track change notification overlay (hide when panel is expanded — already visible)
                if viewModel.currentState != .expanded {
                    trackChangeNotificationOverlay
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(animationForState, value: viewModel.currentState)
            .panGesture(axis: .down) { _, phase in
                guard phase == .began, viewModel.currentState != .expanded else { return }
                viewModel.forceExpand()
            }
            .panGesture(axis: .up) { _, phase in
                guard phase == .began, viewModel.currentState == .expanded else { return }
                viewModel.collapse()
            }
        }
        .ignoresSafeArea()
        // Force dark colour scheme on every view inside the notch panel.
        // The chrome is solid black, so `.primary` text and SF Symbol
        // tints must resolve to white regardless of the user's macOS
        // appearance setting. This single environment override replaces
        // hand-tinting every Text/Image in the widget tree.
        .environment(\.colorScheme, .dark)
        .environment(\.notchHostWindow, hostWindow)
    }

    // MARK: - Panel Content

    @ViewBuilder
    private func panelContent(in geo: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            // Top row: wings flanking the notch (each wing has its own background)
            wingsRow(in: geo)

            // Expanded content — always rendered, height-animated + clipped.
            // Top corners are square so the panel meets the wings flush
            // (no desktop-strip gap between them); only the bottom corners
            // are rounded.
            expandedContent
                // Force the inner content to lay out within `panelWidth`.
                // Without this hard frame, a widget whose natural content
                // exceeds the wing-derived width (e.g. KBO's extra-innings
                // linescore) draws outside the parent VStack — the
                // `.background` then paints chrome at the wider natural
                // width, leaving a visible step where the wings end. Each
                // widget is responsible for declaring a `preferredPanelWidth`
                // that fits its current state; if it doesn't, content gets
                // visibly clipped here (loud failure, not silent chrome step).
                .frame(width: viewModel.panelWidth, alignment: .top)
                .background(panelBackground)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: viewModel.panelCornerRadius,
                        bottomTrailingRadius: viewModel.panelCornerRadius,
                        topTrailingRadius: 0
                    )
                )
                .frame(height: viewModel.expandedHeight, alignment: .top)
                .clipped()
                .allowsHitTesting(viewModel.currentState == .expanded)
        }
        .frame(width: viewModel.panelWidth)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Panel Background

    /// Pure-black panel background. The display's hardware notch is
    /// pure black, so anything lighter shows a visible seam against the
    /// cutout. No translucent material — the chrome must not bleed the
    /// desktop colour through.
    @ViewBuilder
    private var panelBackground: some View {
        Color.black
    }

    // MARK: - Wings Row

    @ViewBuilder
    private func wingsRow(in geo: GeometryProxy) -> some View {
        // Wings render at the width NotchViewModel decides — derived from
        // the active widget's `preferredPanelWidth` (or boosted briefly
        // for a track-change preview). Content fills that width. We
        // deliberately don't use `.fixedSize` + content measurement: the
        // measurement-driven path produced unstable widths (snapping
        // wider on hover, clipping on the wing edge in panel mode when
        // the natural content was wider than the panel-derived width).
        //
        // Wing-bottom rounding is driven by `wingsFlat`, *not* by the
        // panel's animating height — because the corner snap needs to
        // *lead* on expand (corners flatten before the panel grows) and
        // *lag* on collapse (panel shrinks fully before corners round
        // back). NotchViewModel sequences `wingsFlat` separately from
        // `expandedHeight` to make that happen.
        let wingBottomRadius: CGFloat = viewModel.wingsFlat ? 0 : viewModel.panelCornerRadius

        HStack(spacing: 0) {
            leftWing
                .frame(width: viewModel.wingWidth, height: viewModel.notchGeometry.notchHeight)
                .background(panelBackground)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: wingBottomRadius,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0
                    )
                )

            // Fill the area beneath the hardware notch with the same
            // panel background. On Macs with a real notch this paints
            // behind the screen cutout (invisible); on display configs
            // without a notch (external monitors, non-notch MBPs) it
            // bridges the wings into one continuous bar instead of
            // leaving a desktop-coloured strip showing through.
            Color.black
                .frame(width: viewModel.notchGeometry.notchWidth,
                       height: viewModel.notchGeometry.notchHeight)

            rightWing
                .frame(width: viewModel.wingWidth, height: viewModel.notchGeometry.notchHeight)
                .background(panelBackground)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: wingBottomRadius,
                        topTrailingRadius: 0
                    )
                )
        }
        .onPreferenceChange(WingHitZonesKey.self) { zones in
            // De-dupe by button id (last writer wins) — SwiftUI may emit
            // multiple values for the same view across hover transitions
            // (e.g. controls at .opacity(0)).
            var seen: [WingButton: WingHitZone] = [:]
            for z in zones { seen[z.button] = z }
            viewModel.wingHitZones = Array(seen.values)
        }
    }

    // MARK: - Debug Zone Overlay

    @ViewBuilder
    private func debugZoneOverlay(in geo: GeometryProxy) -> some View {
        let notchGeo = viewModel.notchGeometry
        let notchW = notchGeo.notchWidth
        let notchH = notchGeo.notchHeight
        let panelW = viewModel.panelWidth
        let windowWidth = panelW + 40
        let centerX = windowWidth / 2

        ZStack(alignment: .topLeading) {
            // hoverZone = expand zone (full wing area)
            Rectangle()
                .fill(Color.red.opacity(0.15))
                .border(Color.red, width: 1)
                .frame(width: panelW, height: notchH + 5)
                .offset(x: centerX - panelW / 2, y: 0)

            // Hover timer progress
            if viewModel.debugHoverElapsed > 0 {
                let duration = viewModel.debugHoverDuration
                let elapsed = viewModel.debugHoverElapsed
                let progress = min(elapsed / max(duration, 0.01), 1.0)

                VStack(spacing: 2) {
                    // Progress bar
                    GeometryReader { _ in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white.opacity(0.2))
                            RoundedRectangle(cornerRadius: 3)
                                .fill(progress >= 1.0 ? Color.green : Color.yellow)
                                .frame(width: 120 * progress)
                        }
                    }
                    .frame(width: 120, height: 6)

                    Text(String(format: "%.1f / %.1fs", elapsed, duration))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white)
                }
                .offset(x: centerX - 60, y: notchH + 4)
            }

            // State label
            Text("state: \(String(describing: viewModel.currentState))")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.green)
                .offset(x: centerX + 70, y: notchH + 6)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Wing Contents

    @ViewBuilder
    private var leftWing: some View {
        // Other widgets take over the left wing (the album-art slot) when
        // they have live state to show. The right wing stays anchored to
        // the music info because "what's playing" is the highest-signal
        // thing on the notch — losing it for a Timer/FileShelf isn't worth it.
        if viewModel.currentExpandedWidgetID != "music-player",
           let active = widgetRegistry.widget(for: viewModel.currentExpandedWidgetID),
           active.isEnabled,
           hasContentToShow(active) {
            active.makeCompactView()
                .transition(.opacity)
        } else if let musicWidget = widgetRegistry.widget(for: "music-player"),
                  let actualWidget = musicWidget.wrapped as? MusicPlayerWidget,
                  musicWidget.isEnabled {
            actualWidget.makeCompactView()
                .transition(.opacity)
        } else {
            Image(systemName: "music.note")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var rightWing: some View {
        // Right wing follows whichever widget is selected in the panel
        // switcher AND has content worth surfacing (`hasContentToShow`).
        // Same rule as the left wing — without it, selecting KBO with no
        // pinned live game would leave one wing on music (fallback) and
        // the other on a stray KBO placeholder.
        let selectedID = viewModel.currentExpandedWidgetID

        if selectedID == "kbo",
           let kboWidget = widgetRegistry.widget(for: "kbo"),
           let kbo = kboWidget.wrapped as? KBOWidget,
           kboWidget.isEnabled,
           hasContentToShow(kboWidget) {
            kbo.makeCompactInfoView()
                .transition(.opacity)
        } else if let musicWidget = widgetRegistry.widget(for: "music-player"),
                  let actualWidget = musicWidget.wrapped as? MusicPlayerWidget,
                  musicWidget.isEnabled {
            actualWidget.makeCompactInfoView()
                .transition(.opacity)
        } else {
            Image(systemName: "music.note")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
    }

    /// True when the widget has live state worth surfacing in the wing.
    /// Returning false here causes the wing to fall back to music.
    private func hasContentToShow(_ widget: AnyNotchWidget) -> Bool {
        if let fs = widget.wrapped as? FileShelfWidget {
            return !fs.viewModel.items.isEmpty
        }
        if let timer = widget.wrapped as? TimerWidget {
            return timer.viewModel.displayTime > 0 || timer.viewModel.isActive
        }
        if let kbo = widget.wrapped as? KBOWidget {
            // Hold the wing while the user is browsing a non-today date —
            // they're clearly in the KBO context and flipping to music
            // wings under a KBO panel is jarring. Otherwise only claim the
            // wing for a pinned live game; static "vs" or final scores
            // aren't useful at wing-glance scale.
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
                .padding(.horizontal, 20)

            WidgetSwitcherBar(
                widgets: widgetRegistry.enabledWidgets,
                currentID: Binding(
                    get: { viewModel.currentExpandedWidgetID },
                    set: { viewModel.currentExpandedWidgetID = $0 }
                )
            )

            // Body of the currently selected widget. If the selected widget
            // gets disabled while we're showing it, fall back to the first
            // enabled one (and update the persisted selection).
            Group {
                if let widget = widgetRegistry.widget(for: viewModel.currentExpandedWidgetID),
                   widget.isEnabled {
                    widget.makeExpandedView()
                        .id(widget.id)
                        .transition(.opacity)
                } else if let first = widgetRegistry.enabledWidgets.first {
                    first.makeExpandedView()
                        .id(first.id)
                        .transition(.opacity)
                        .onAppear { viewModel.currentExpandedWidgetID = first.id }
                } else {
                    Text("No widgets enabled")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 100)
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    // MARK: - HUD Overlay

    @ViewBuilder
    private var hudOverlay: some View {
        let hudWidget = widgetRegistry.widget(for: "hud")
        if let hud = hudWidget, hud.isEnabled {
            VStack {
                hud.makeCompactView()
                    .padding(.top, viewModel.notchGeometry.notchHeight + 8)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: - Track Change Notification Overlay

    @ViewBuilder
    private var trackChangeNotificationOverlay: some View {
        if let musicWidget = widgetRegistry.widget(for: "music-player"),
           let actualWidget = musicWidget.wrapped as? MusicPlayerWidget,
           actualWidget.viewModel.showTrackChangeNotification,
           let trackInfo = actualWidget.viewModel.trackChangeInfo {

            // Use viewModel artwork (reactive via @Observable)
            let liveArtwork = actualWidget.viewModel.currentArtwork

            HStack(spacing: 12) {
                // Album art
                if let artwork = liveArtwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            LinearGradient(
                                colors: [Color.purple.opacity(0.4), Color.blue.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                        .overlay {
                            Image(systemName: "music.note")
                                .font(.system(size: 18, weight: .light))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                }

                // Track info
                VStack(alignment: .leading, spacing: 2) {
                    Text(trackInfo.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(trackInfo.artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(themeManager.currentTheme.panelMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            .frame(width: 320)
            .padding(.top, viewModel.notchGeometry.notchHeight + 16)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: actualWidget.viewModel.showTrackChangeNotification)
        }
    }

    // MARK: - Animation

    private var animationForState: Animation? {
        guard settings.animationsEnabled else { return nil }

        switch viewModel.currentState {
        case .idle: return AnimationTokens.collapse
        case .hovering: return AnimationTokens.expandHover
        case .expanded: return AnimationTokens.expandClick
        }
    }
}

/// Attach FileShelfDropDelegate to a view only when the FileShelf widget is
/// available (registered + enabled). When it's not, the modifier is a no-op
/// so we don't claim drag events the user is sending elsewhere.
private struct FileShelfDropOnWings: ViewModifier {
    let fileShelf: FileShelfWidget?

    func body(content: Content) -> some View {
        if let fileShelf, fileShelf.isEnabled {
            content.onDrop(
                of: [.fileURL],
                delegate: FileShelfDropDelegate(viewModel: fileShelf.viewModel)
            )
        } else {
            content
        }
    }
}
