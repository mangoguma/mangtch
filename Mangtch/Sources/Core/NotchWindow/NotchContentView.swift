import SwiftUI

struct NotchContentView: View {
    @State private var viewModel = NotchViewModel.shared
    @State private var widgetRegistry = WidgetRegistry.shared
    @State private var settings = SettingsManager.shared
    @ObservedObject private var themeEngine = ThemeEngine.shared

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
        }
        .ignoresSafeArea()
    }

    // MARK: - Panel Content

    @ViewBuilder
    private func panelContent(in geo: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            // Top row: wings flanking the notch (each wing has its own background)
            wingsRow(in: geo)

            // Expanded content — always rendered, height-animated + clipped
            // As expandedHeight shrinks from maxExpandedHeight → 0,
            // the content is clipped from the bottom (like a drawer closing).
            expandedContent
                .background(themeEngine.currentTheme.panelMaterial)
                .clipShape(
                    RoundedRectangle(cornerRadius: viewModel.panelCornerRadius)
                )
                .frame(height: viewModel.expandedHeight, alignment: .top)
                .clipped()
                .allowsHitTesting(viewModel.currentState == .expanded)
        }
        .frame(width: viewModel.panelWidth)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Wings Row

    @ViewBuilder
    private func wingsRow(in geo: GeometryProxy) -> some View {
        let fileShelf = (widgetRegistry.widget(for: "file-shelf")?.wrapped as? FileShelfWidget)

        HStack(spacing: 0) {
            // Left wing (always visible)
            leftWing
                .frame(width: viewModel.wingWidth)
                .frame(height: viewModel.notchGeometry.notchHeight)
                .background(themeEngine.currentTheme.panelMaterial)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: viewModel.panelCornerRadius,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0
                    )
                )

            // Spacer for the physical notch
            Spacer()
                .frame(width: viewModel.notchGeometry.notchWidth)

            // Right wing (always visible)
            rightWing
                .frame(width: viewModel.wingWidth)
                .frame(height: viewModel.notchGeometry.notchHeight)
                .background(themeEngine.currentTheme.panelMaterial)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: viewModel.panelCornerRadius,
                        topTrailingRadius: 0
                    )
                )
        }
        // Treat the whole wings row as a drop target. Without this, the user
        // has to hover the file-shelf compact icon precisely while dragging,
        // which is awkward on a 14pt target. The contentShape ensures the
        // notch gap (a SwiftUI Spacer) is hit-tested too — without it, drags
        // over the empty middle don't register.
        .contentShape(Rectangle())
        .modifier(FileShelfDropOnWings(fileShelf: fileShelf))
    }

    // MARK: - Wing Contents

    @ViewBuilder
    private var leftWing: some View {
        // Music player compact artwork (album art + playing indicator)
        if let musicWidget = widgetRegistry.widget(for: "music-player"),
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
        // The right wing mirrors whichever widget the user last selected in
        // the switcher, in every state. Music keeps the dedicated info view
        // (track + hover-controls); other widgets reuse their compact view.
        if viewModel.currentExpandedWidgetID != "music-player",
           let active = widgetRegistry.widget(for: viewModel.currentExpandedWidgetID),
           active.isEnabled {
            active.makeCompactView()
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
            .background(themeEngine.currentTheme.panelMaterial)
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
