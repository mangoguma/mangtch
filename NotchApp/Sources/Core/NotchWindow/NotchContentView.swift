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
                    .background(themeEngine.currentTheme.panelMaterial)
                    .clipShape(
                        RoundedRectangle(cornerRadius: viewModel.panelCornerRadius)
                    )

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
    }

    // MARK: - Panel Content

    @ViewBuilder
    private func panelContent(in geo: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            // Top row: wings flanking the notch
            wingsRow(in: geo)

            // Expanded content (only when expanded)
            if viewModel.currentState == .expanded {
                expandedContent
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(width: viewModel.panelWidth)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Wings Row

    @ViewBuilder
    private func wingsRow(in geo: GeometryProxy) -> some View {
        HStack(spacing: 0) {
            // Left wing (always visible)
            leftWing
                .frame(width: viewModel.wingWidth)
                .frame(height: viewModel.notchGeometry.notchHeight)

            // Spacer for the physical notch
            Spacer()
                .frame(width: viewModel.notchGeometry.notchWidth)

            // Right wing (only on hover/expanded)
            if viewModel.currentState == .hovering || viewModel.currentState == .expanded {
                rightWing
                    .frame(width: viewModel.wingWidth)
                    .frame(height: viewModel.notchGeometry.notchHeight)
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
    }

    // MARK: - Wing Contents

    @ViewBuilder
    private var leftWing: some View {
        let leftWidgets = widgetRegistry.widgets(for: .leftWing)
        if let first = leftWidgets.first {
            first.makeCompactView()
                .transition(.opacity)
        } else {
            // Default: file shelf icon
            Image(systemName: "tray")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var rightWing: some View {
        let rightWidgets = widgetRegistry.widgets(for: .rightWing)
        if let first = rightWidgets.first {
            first.makeCompactView()
                .transition(.opacity)
        } else {
            // Default: music note
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

            // Main widget content
            let centerWidgets = widgetRegistry.enabledWidgets
            if let musicWidget = widgetRegistry.widget(for: "music-player"), musicWidget.isEnabled {
                musicWidget.makeExpandedView()
            } else if let first = centerWidgets.first {
                first.makeExpandedView()
            } else {
                Text("No widgets enabled")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            }

            // Widget tabs at bottom
            if centerWidgets.count > 1 {
                widgetTabs
            }
        }
    }

    // MARK: - Widget Tabs

    @ViewBuilder
    private var widgetTabs: some View {
        HStack(spacing: 16) {
            ForEach(widgetRegistry.enabledWidgets) { widget in
                Button(action: {
                    // TODO: switch active widget
                }) {
                    VStack(spacing: 2) {
                        Image(systemName: widget.icon)
                            .font(.system(size: 14))
                        Text(widget.displayName)
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
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
