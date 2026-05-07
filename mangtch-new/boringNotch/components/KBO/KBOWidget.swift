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
        let rowSlot = max(KBOLayoutTokens.rowSlotMinWidth, starterSlot)
        let teamSide = KBOLayoutTokens.teamSideWidth
        let closed = rowSlot * 2
            + KBOLayoutTokens.scoreColumnWidth
            + teamSide * 2
            + KBOLayoutTokens.statusChipWidth
            + KBOLayoutTokens.panelChildSpacing * CGFloat(KBOLayoutTokens.panelChildGapCount)
            + KBOLayoutTokens.panelOuterHorizontalPadding
        let ideal: CGFloat
        if let line = viewModel.viewingLinescore {
            let innings = max(line.innings, 9)
            let cellsWidth = CGFloat(innings + KBOLayoutTokens.linescoreInningExtraColumns)
                * KBOLayoutTokens.linescoreTotalsCellWidth
            let gridWidth = KBOLayoutTokens.linescoreTeamLabelWidth + cellsWidth
            let leftSlot = Self.expandedStarterSlotWidth(line.awayStartingPitcher)
            let rightSlot = Self.expandedStarterSlotWidth(line.homeStartingPitcher)
            let open = leftSlot
                + KBOLayoutTokens.openGridGutter
                + gridWidth
                + KBOLayoutTokens.openGridGutter
                + rightSlot
                + KBOLayoutTokens.openOuterPadding
            ideal = max(closed, open)
        } else {
            ideal = closed
        }
        return WidthRange(min: ideal * KBOLayoutTokens.panelMinScale,
                          ideal: ideal,
                          max: LayoutTokens.openCanvasWidth)
    }

    /// Dynamic height — header (24pt) + N game rows (50pt each) + row
    /// gaps + outer vertical padding. When viewing a linescore, the
    /// selected game row replaces its inline form with the inning grid
    /// (taller). Empty-state collapses to a small fixed height.
    var heightRange: HeightRange {
        let header = KBOLayoutTokens.panelHeaderHeight
        let outerPadding = KBOLayoutTokens.panelOuterVerticalPadding
        let rowGap = KBOLayoutTokens.rowGap
        let rowHeight = KBOLayoutTokens.panelHeightRowHeight
        let linescoreHeight = KBOLayoutTokens.panelHeightLinescoreSection
        let count = viewModel.games.count
        let ideal: CGFloat
        if count > 0 {
            var rows = CGFloat(count) * rowHeight + CGFloat(max(count - 1, 0)) * rowGap
            if viewModel.viewingLinescore != nil {
                rows += linescoreHeight
            }
            ideal = header + outerPadding + rows + KBOLayoutTokens.panelHeightFooterSlack
        } else {
            ideal = header + outerPadding + KBOLayoutTokens.panelHeightEmptyExtra
        }
        return HeightRange(min: ideal * KBOLayoutTokens.panelMinScale,
                           ideal: ideal,
                           max: ideal * KBOLayoutTokens.panelMaxHeightScale)
    }

    /// Width needed to render the *expanded* starter slot ("선발" badge +
    /// "P" badge + name). Uses real text metrics so long names like
    /// "로드리게스" never collide with the inning grid.
    @MainActor
    private static func expandedStarterSlotWidth(_ name: String?) -> CGFloat {
        let font = NSFont.systemFont(ofSize: KBOLayoutTokens.expandedStarterFontSize,
                                     weight: .semibold)
        let text = name ?? "—"
        let nameWidth = (text as NSString).size(withAttributes: [.font: font]).width
        return ceil(nameWidth)
            + KBOLayoutTokens.expandedStarterBadgePadding
            + KBOLayoutTokens.expandedStarterRowSpacing
            + KBOLayoutTokens.expandedStarterTrailing
    }

    /// Width of the inline starter slot used by the collapsed game row.
    /// Mirrors `KBOExpandedView.starterSlotWidth` so wing/panel width
    /// matches what the row actually renders.
    @MainActor
    private static func inlineStarterSlotWidth(_ cache: [String: KBOStarters]) -> CGFloat {
        let font = NSFont.systemFont(ofSize: KBOLayoutTokens.inlineStarterFontSize,
                                     weight: .semibold)
        let widest = cache.values
            .flatMap { [$0.away, $0.home] }
            .compactMap { $0 }
            .map { ($0 as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 0
        return max(KBOLayoutTokens.inlineStarterMinWidth,
                   ceil(widest)
                   + KBOLayoutTokens.inlineStarterNameGap
                   + KBOLayoutTokens.inlineStarterBadgeWidth
                   + KBOLayoutTokens.inlineStarterTrailing)
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
