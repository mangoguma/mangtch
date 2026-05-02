import SwiftUI

@MainActor
final class MusicPlayerWidget: NotchWidget {
    let id = "music-player"
    let displayName = "Music Player"
    let icon = "music.note"
    let preferredPosition: WidgetPosition = .leftWing
    var isEnabled: Bool = true

    /// Album art + scrolling track info + transport — fits comfortably
    /// in 480pt; goes wider just makes the marquee scroll less and
    /// leaves dead space.
    var preferredPanelWidth: CGFloat? { 480 }

    let viewModel = MusicPlayerViewModel()

    @MainActor
    func makeCompactView() -> AnyView {
        AnyView(
            CompactArtworkView(viewModel: viewModel)
        )
    }

    /// Right wing compact view: track info with hover controls
    @MainActor
    func makeCompactInfoView() -> AnyView {
        AnyView(
            CompactInfoView(viewModel: viewModel)
        )
    }

    @MainActor
    func makeExpandedView() -> AnyView {
        AnyView(ExpandedPlayerView(viewModel: viewModel))
    }

    func activate() {
        Task { @MainActor in
            viewModel.startObserving()
        }
    }

    func deactivate() {
        Task { @MainActor in
            viewModel.stopObserving()
        }
    }
}
