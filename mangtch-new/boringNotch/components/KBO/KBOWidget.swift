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
    /// wing/panel via `metrics` whenever they change.
    var widthRange: WidthRange {
        // Row-edge slot hosts either the inline starter (non-live) or the
        // live-state diamond/BSO cell (live).
        let starterSlot = Self.inlineStarterSlotWidth(viewModel.startingPitchers)
        let rowSlot = max(80, starterSlot)
        let teamSide: CGFloat = 80
        let closed = rowSlot * 2 + 64 + teamSide * 2 + 64
            + 10 * 5        // HStack(spacing: 10) between 6 children = 5 gaps
            + 28            // .padding(.horizontal, 14)
        let ideal: CGFloat
        if let line = viewModel.viewingLinescore {
            let innings = max(line.innings, 9)
            let cellsWidth = CGFloat(innings + 4) * 22
            let gridWidth = 44 + cellsWidth
            let leftSlot = Self.expandedStarterSlotWidth(line.awayStartingPitcher)
            let rightSlot = Self.expandedStarterSlotWidth(line.homeStartingPitcher)
            let open = leftSlot + 8 + gridWidth + 8 + rightSlot + 16
            ideal = max(closed, open)
        } else {
            ideal = closed
        }
        return WidthRange(min: ideal * 0.8, ideal: ideal, max: LayoutTokens.openCanvasWidth)
    }

    /// Dynamic height — header (24pt) + N game rows (50pt each) + row
    /// gaps + outer vertical padding. When viewing a linescore, the
    /// selected game row replaces its inline form with the inning grid
    /// (taller). Empty-state collapses to a small fixed height.
    var heightRange: HeightRange {
        let header: CGFloat = 24
        let outerPadding: CGFloat = 16  // .padding(.vertical, 8) top+bottom
        let rowGap: CGFloat = 4
        let rowHeight: CGFloat = 50
        let linescoreHeight: CGFloat = 110
        let count = viewModel.games.count
        let ideal: CGFloat
        if count > 0 {
            var rows = CGFloat(count) * rowHeight + CGFloat(max(count - 1, 0)) * rowGap
            if viewModel.viewingLinescore != nil {
                rows += linescoreHeight
            }
            ideal = header + outerPadding + rows + 6
        } else {
            ideal = header + outerPadding + 60
        }
        return HeightRange(min: ideal * 0.8, ideal: ideal, max: ideal * 1.5)
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
