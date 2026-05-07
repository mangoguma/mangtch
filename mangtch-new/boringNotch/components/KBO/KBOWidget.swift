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
    /// `startingPitchers` are both `@Observable`, BoringViewModel re-snaps
    /// wing/panel via `panelModeWingWidth` whenever they change.
    var preferredPanelWidth: CGFloat? {
        // Row-edge slot hosts either the inline starter (non-live) or the
        // live-state diamond/BSO cell (live). Width is the max of the
        // widest cached pitcher-name slot and the 80pt the live cell
        // wants, so swapping content between rows doesn't reflow.
        let starterSlot = Self.inlineStarterSlotWidth(viewModel.startingPitchers)
        let rowSlot = max(80, starterSlot)
        // Closed-row layout: 2x slot + score(64) + 2x team flex (logo 22
        // + name ~58 + spacing) + statusChip(64) + outer paddings.
        // Team-side natural width up to ~80pt covers every Korean team
        // name comfortably.
        let teamSide: CGFloat = 80
        let closed = rowSlot * 2 + 64 + teamSide * 2 + 64
            + 10 * 5        // HStack(spacing: 10) between 6 children = 5 gaps
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
