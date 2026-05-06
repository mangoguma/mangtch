import SwiftUI
import AppKit

@MainActor
final class KBOWidget: NotchWidget {
    let id = "kbo"
    let displayName = "KBO"
    let icon = "baseball"
    let preferredPosition: WidgetPosition = .leftWing
    var isEnabled: Bool = true

    /// Panel width is content-driven in both closed and open modes:
    /// closed grows with the widest cached starter name (so collapsed
    /// rows never truncate either pitcher or team name), open additionally
    /// factors in the inning grid. `viewingLinescore` and
    /// `startingPitchers` are both `@Observable`, NotchViewModel re-snaps
    /// wing/panel via `setupWidgetWidthObserver` whenever they change.
    var preferredPanelWidth: CGFloat? {
        let inlineSlot = Self.inlineStarterSlotWidth(viewModel.startingPitchers)
        // Closed-row layout: 2x starter slot + score(64) + 2x team flex
        // (logo 22 + name ~58 + spacing) + livecell(80) + statusChip(64)
        // + outer paddings/spacings. We assume team-side natural width
        // up to ~80pt covers every Korean team name comfortably.
        let teamSide: CGFloat = 80
        // The 80pt live-state slot only renders for live games; otherwise
        // the row drops it entirely so non-live days don't reserve dead
        // air between the home starter and the "종료" chip.
        let anyLive = viewModel.games.contains(where: { $0.isLive })
        let liveCellSlot: CGFloat = anyLive ? 80 : 0
        let liveGaps: Int = anyLive ? 6 : 5
        let closed = inlineSlot * 2 + 64 + teamSide * 2 + liveCellSlot + 64
            + 10 * CGFloat(liveGaps)
            + 28            // .padding(.horizontal, 14)
        guard let line = viewModel.viewingLinescore else { return closed }

        let innings = max(line.innings, 9)
        let cellsWidth = CGFloat(innings + 4) * 22
        let gridWidth = 44 + cellsWidth
        let leftSlot = Self.expandedStarterSlotWidth(line.awayStartingPitcher)
        let rightSlot = Self.expandedStarterSlotWidth(line.homeStartingPitcher)
        let open = leftSlot + 8 + gridWidth + 8 + rightSlot + 16
        return max(closed, open)
    }

    /// Width needed to render the *expanded* starter slot ("선발" badge +
    /// "P" badge + name). Uses real text metrics so long names like
    /// "로드리게스" never collide with the inning grid.
    @MainActor
    private static func expandedStarterSlotWidth(_ name: String?) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let text = name ?? "—"
        let nameWidth = (text as NSString).size(withAttributes: [.font: font]).width
        return ceil(nameWidth) + 14 + 3 + 6
    }

    /// Width of the inline starter slot used by the collapsed game row.
    /// Mirrors `KBOExpandedView.starterSlotWidth` so wing/panel width
    /// matches what the row actually renders.
    @MainActor
    private static func inlineStarterSlotWidth(_ cache: [String: KBOStarters]) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
        let widest = cache.values
            .flatMap { [$0.away, $0.home] }
            .compactMap { $0 }
            .map { ($0 as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 0
        return max(70, ceil(widest) + 4 + 12 + 8)
    }

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
