import SwiftUI

struct NotchContentView: View {
    @State private var viewModel = NotchViewModel.shared
    @State private var widgetRegistry = WidgetRegistry.shared
    @State private var settings = SettingsManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                panelContent(in: geo)

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

    /// Solid near-black panel background. Pure `Color.black` made faint
    /// strokes (empty B/S/O rings, secondary text, divider lines)
    /// disappear into the canvas — `Color(white: 0.14)` is dark enough to
    /// read as "black panel" while still letting low-contrast elements
    /// breathe. No translucent material: the chrome must not bleed the
    /// desktop colour through.
    @ViewBuilder
    private var panelBackground: some View {
        Color(white: 0.14)
    }

    // MARK: - Wings Row

    @ViewBuilder
    private func wingsRow(in geo: GeometryProxy) -> some View {
        // Wings size to their content via PreferenceKey measurement. The
        // inner content renders at its intrinsic horizontal size (via
        // `.fixedSize`), GeometryReader measures it, and `onPreferenceChange`
        // pushes the max of (left, right) back to NotchViewModel so panel
        // and gesture math stay in sync.
        //
        // Wing-bottom rounding is driven by `wingsFlat`, *not* by the
        // panel's animating height — because the corner snap needs to
        // *lead* on expand (corners flatten before the panel grows) and
        // *lag* on collapse (panel shrinks fully before corners round
        // back). NotchViewModel sequences `wingsFlat` separately from
        // `expandedHeight` to make that happen. Each transition uses its
        // own `withAnimation`, so SwiftUI smoothly interpolates the
        // radius in step with that snap rather than the panel's spring.
        let wingBottomRadius: CGFloat = viewModel.wingsFlat ? 0 : viewModel.panelCornerRadius

        HStack(spacing: 0) {
            leftWing
                .fixedSize(horizontal: true, vertical: false)
                .background(WingMeasure(side: .left))
                .frame(width: viewModel.wingWidth, alignment: .center)
                .frame(height: viewModel.notchGeometry.notchHeight)
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
            Color(white: 0.14)
                .frame(width: viewModel.notchGeometry.notchWidth,
                       height: viewModel.notchGeometry.notchHeight)

            rightWing
                .fixedSize(horizontal: true, vertical: false)
                .background(WingMeasure(side: .right))
                .frame(width: viewModel.wingWidth, alignment: .center)
                .frame(height: viewModel.notchGeometry.notchHeight)
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
        .onPreferenceChange(WingContentWidthKey.self) { measured in
            // Take the larger side so both wings stay equal width and the
            // notch cutout in the panel keeps centred over the hardware
            // notch. Add a small horizontal margin so content doesn't kiss
            // the curve, then clamp to the configured min/max.
            let proposed = max(measured.left, measured.right) + 16
            let clamped = min(max(proposed, NotchViewModel.minWingWidth),
                              NotchViewModel.maxWingWidth)
            if abs(viewModel.compactWingWidth - clamped) > 0.5 {
                viewModel.compactWingWidth = clamped
            }
        }
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
            // Only claim the wing while the pinned game is actually being
            // played. Scheduled / finished / unpinned all fall back to
            // music, since a static "vs" or final score isn't useful at
            // wing-glance scale.
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

// MARK: - Wing measurement

/// Reports the natural intrinsic width of each wing's content. The HStack
/// reads `.left` and `.right` independently and the parent picks the
/// max so both wings stay symmetric around the notch.
private struct WingContentWidths: Equatable {
    var left: CGFloat = 0
    var right: CGFloat = 0
}

private struct WingContentWidthKey: PreferenceKey {
    static let defaultValue = WingContentWidths()
    static func reduce(value: inout WingContentWidths, nextValue: () -> WingContentWidths) {
        let next = nextValue()
        value.left = max(value.left, next.left)
        value.right = max(value.right, next.right)
    }
}

/// Reads the size of the wing content it's attached to as a `.background`,
/// then writes that width into a `WingContentWidthKey` preference under
/// the appropriate side. Vertical size is ignored — wing height is fixed
/// to the notch.
private struct WingMeasure: View {
    enum Side { case left, right }
    let side: Side

    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: WingContentWidthKey.self,
                value: side == .left
                    ? WingContentWidths(left: proxy.size.width, right: 0)
                    : WingContentWidths(left: 0, right: proxy.size.width)
            )
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
