import SwiftUI
import AppKit

@MainActor
final class KBOWidget: NotchWidget {
    let id = "kbo"
    let displayName = "KBO"
    let icon = "baseball"
    let preferredPosition: WidgetPosition = .leftWing
    var isEnabled: Bool = true

    /// Width is locked to the global panel canvas so switching widgets
    /// (Music ↔ KBO ↔ Timer) never resizes the wings — the compact-view
    /// swap would otherwise show as a wobble because each widget returns
    /// a structurally different `makeCompactView()`. KBO's expanded
    /// content (5 game rows + linescore grid) is sized to fit this width;
    /// the row internals scale to the available `panelWidth`, not the
    /// other way around.
    var widthRange: WidthRange { .fixed(LayoutTokens.panelMaxWidth) }

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
            if viewModel.viewingLinescore != nil {
                rows += linescoreHeight
            }
            ideal = header + outerPadding + rows + KBOLayoutTokens.panelHeightFooterSlack
        } else {
            // panelCornerRadius slack so the rounded bottom edge doesn't
            // clip into the centered empty/loading/error message.
            ideal = header
                + KBOLayoutTokens.bodyOuterSpacing
                + KBOLayoutTokens.emptyStateMinHeight
                + outerPadding
                + LayoutTokens.panelCornerRadius
        }
        return HeightRange(min: ideal * KBOLayoutTokens.panelMinScale,
                           ideal: ideal,
                           max: ideal * KBOLayoutTokens.panelMaxHeightScale)
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
