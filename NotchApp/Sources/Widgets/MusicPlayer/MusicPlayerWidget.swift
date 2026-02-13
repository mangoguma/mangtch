import SwiftUI

@MainActor
final class MusicPlayerWidget: NotchWidget {
    let id = "music-player"
    let displayName = "Music Player"
    let icon = "music.note"
    let preferredPosition: WidgetPosition = .rightWing
    var isEnabled: Bool = true

    let viewModel = MusicPlayerViewModel()

    @MainActor
    func makeCompactView() -> AnyView {
        AnyView(
            NowPlayingView(viewModel: viewModel)
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
