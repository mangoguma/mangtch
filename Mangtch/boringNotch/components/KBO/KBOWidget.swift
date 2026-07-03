import SwiftUI
import AppKit

@MainActor
final class KBOWidget: NotchWidget {
    let id = "kbo"
    let displayName = "KBO"
    let icon = "baseball"
    var isEnabled: Bool = true

    /// Mid-priority. Wins over Music whenever a live game (or non-today
    /// browsing) is in progress; loses to Timer (the user explicitly
    /// started a countdown — that's the most foreground intent).
    let wingPriority: Int = 10

    /// Hold the wings while the user is *actively browsing* a non-today date
    /// (panel open) — they're clearly in the KBO context and flipping to Music
    /// under a KBO panel is jarring. Gated on `isNotchOpen` so a stale date
    /// left behind while collapsed (e.g. after a KST midnight rollover, where
    /// `displayedDate` only re-anchors on the next open) doesn't squat on the
    /// wings all day with no live game. When collapsed we only claim for a
    /// live pinned game.
    @MainActor
    var claimsWings: Bool {
        if viewModel.isNotchOpen && !viewModel.isShowingToday { return true }
        return viewModel.selectedGame?.isLive == true
    }

    /// Content-driven width (re-enabled in phase 8b). The closed-row layout
    /// drives `min` / `ideal` so the panel never leaves a starter name
    /// truncated; viewing a linescore grows `ideal` to also clear the
    /// inning grid plus expanded starter slots. Hard-capped at
    /// `LayoutTokens.panelMaxWidth` (640) — beyond that we'd outgrow the
    /// Music canvas, which is the global ceiling.
    ///
    /// Both `viewModel.startingPitchers` and `viewModel.viewingLinescore`
    /// are `@Observable`; `BoringViewModel.recomputeMetrics()` re-fires
    /// resolution under `withObservationTracking` whenever they mutate.
    var widthRange: WidthRange {
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

        let cap = LayoutTokens.panelMaxWidth
        let clampedIdeal = min(ideal, cap)
        // Min defends against starter-cache empty / first-frame races —
        // never let the panel collapse below the closed-row minimum.
        let minClosed = KBOLayoutTokens.rowSlotMinWidth * 2
            + KBOLayoutTokens.scoreColumnWidth
            + teamSide * 2
            + KBOLayoutTokens.statusChipWidth
            + KBOLayoutTokens.panelChildSpacing * CGFloat(KBOLayoutTokens.panelChildGapCount)
            + KBOLayoutTokens.panelOuterHorizontalPadding
        return WidthRange(min: min(minClosed, cap), ideal: clampedIdeal, max: cap)
    }

    /// Width needed to render the *expanded* starter slot ("선발" badge +
    /// "P" badge + name). Uses real text metrics so long Korean names like
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

    /// Dynamic height — header (24pt) + N game rows (50pt each) + row
    /// gaps + outer vertical padding. When viewing a linescore, the
    /// selected game row replaces its inline form with the inning grid
    /// (taller). Empty / loading / error states share a fixed minHeight
    /// box (`emptyStateMinHeight`) — the formula must reserve space for
    /// header + body gutter + that box, otherwise SwiftUI clips the
    /// "경기가 없어요" line.
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
            // Reserve the expansion section as soon as a row is expanded,
            // not only once the linescore JSON has landed. Pre-game and
            // failed-fetch rows leave `viewingLinescore` nil but still
            // render the inline placeholder ("경기 시작 전이라…"), and
            // without this allowance the panel stayed at collapsed height
            // and clipped the placeholder out from under its own row.
            if viewModel.viewingGameID != nil {
                rows += linescoreHeight
            }
            ideal = header + outerPadding + rows + KBOLayoutTokens.panelHeightFooterSlack
        } else {
            // No extra corner-radius slack here — `PanelLayoutMetrics.resolve`
            // already bakes in `panelBottomInset` (12pt) and `ContentView`
            // applies the same 12pt below the widget Group, plus KBO's own
            // `bodyOuterVerticalPadding` (8pt) sits beneath the empty box.
            // Adding `panelCornerRadius` on top made the formula 14pt taller
            // than the rendered intrinsic, so the GR-measured value shrunk
            // the NSPanel below the formula bootstrap on empty days and the
            // bottom rounded corner clipped the placeholder text.
            ideal = header
                + KBOLayoutTokens.bodyOuterSpacing
                + KBOLayoutTokens.emptyStateMinHeight
                + outerPadding
        }
        // Defensive cap so the panel can't outgrow the viewport on small
        // displays — KBO regular season tops out at 5 games/day so this
        // is a no-op in normal use; matters only if the formula's per-row
        // estimate drifts upward later.
        let safeMax = (NSScreen.main?.visibleFrame.height ?? 800)
            * KBOLayoutTokens.panelScreenSafeFraction
        let absoluteMax = min(safeMax, KBOLayoutTokens.panelAbsoluteMaxHeight)
        let clampedIdeal = min(ideal, absoluteMax)
        let clampedMax = min(ideal * KBOLayoutTokens.panelMaxHeightScale,
                             absoluteMax)
        return HeightRange(min: clampedIdeal * KBOLayoutTokens.panelMinScale,
                           ideal: clampedIdeal,
                           max: clampedMax)
    }

    let viewModel = KBOViewModel()

    @MainActor
    func makeLeftWingView() -> AnyView {
        AnyView(KBOCompactView(viewModel: viewModel))
    }

    @MainActor
    func makeRightWingView() -> AnyView {
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
