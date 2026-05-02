import SwiftUI

@MainActor
final class KBOWidget: NotchWidget {
    let id = "kbo"
    let displayName = "KBO"
    let icon = "baseball"
    let preferredPosition: WidgetPosition = .leftWing
    var isEnabled: Bool = true

    /// 5 game rows + day-nav + optional inline 9-column linescore.
    /// 540pt keeps it compact while still showing all team logos,
    /// scores, live state, and the inning grid without truncation.
    var preferredPanelWidth: CGFloat? { 540 }

    let viewModel = KBOViewModel()

    @MainActor
    func makeCompactView() -> AnyView {
        AnyView(KBOCompactView(viewModel: viewModel))
    }

    /// Right-wing companion view: live B/S/O + bases + pitcher/batter.
    /// Mirrors MusicPlayerWidget.makeCompactInfoView(); NotchContentView
    /// uses it whenever KBO is the panel-selected widget AND a live game
    /// is pinned. Falls back to a placeholder when there's no live state.
    @MainActor
    func makeCompactInfoView() -> AnyView {
        AnyView(KBORightWingContainer(viewModel: viewModel))
    }

    @MainActor
    func makeExpandedView() -> AnyView {
        AnyView(KBOExpandedView(viewModel: viewModel))
    }

    func activate() {
        Task { @MainActor in
            viewModel.startMonitoring()
        }
    }

    func deactivate() {
        Task { @MainActor in
            viewModel.stopMonitoring()
        }
    }
}
