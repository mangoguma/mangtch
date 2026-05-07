import SwiftUI

/// Layout constants for the KBO widget. Domain-scoped because the KBO
/// widget has its own information density (linescore grid, bases diamond,
/// inline starter pills) that doesn't generalize to other widgets.
enum KBOLayoutTokens {
    // MARK: Widget panel sizing — KBOWidget.widthRange
    static let rowSlotMinWidth: CGFloat = 80
    static let teamSideWidth: CGFloat = 80
    static let scoreColumnWidth: CGFloat = 64
    static let statusChipWidth: CGFloat = 64
    static let panelChildSpacing: CGFloat = 10           // HStack between 6 row children
    static let panelChildGapCount: Int = 5               // 6 children → 5 gaps
    static let panelOuterHorizontalPadding: CGFloat = 28 // 14*2 (row outer .padding(.horizontal,14))
    static let openGridGutter: CGFloat = 8               // gap between starter slot and grid
    static let openOuterPadding: CGFloat = 16

    // MARK: Inline starter slot — collapsed game row
    static let inlineStarterFontSize: CGFloat = 10.5
    static let inlineStarterMinWidth: CGFloat = 70
    static let inlineStarterNameGap: CGFloat = 4   // name ↔ badge
    static let inlineStarterBadgeWidth: CGFloat = 12
    static let inlineStarterTrailing: CGFloat = 8

    // MARK: Expanded starter slot — flanks linescore grid
    static let expandedStarterFontSize: CGFloat = 11
    static let expandedStarterBadgePadding: CGFloat = 14
    static let expandedStarterRowSpacing: CGFloat = 3
    static let expandedStarterTrailing: CGFloat = 6

    // MARK: Linescore grid
    static let linescoreInningCellWidth: CGFloat = 20
    static let linescoreInningCellHeight: CGFloat = 20
    static let linescoreTotalsCellWidth: CGFloat = 22
    static let linescoreTotalsCellHeight: CGFloat = 20
    static let linescoreTeamLabelWidth: CGFloat = 44
    static let linescoreInningExtraColumns: Int = 4   // R H E B
    static let linescoreSidePadding: CGFloat = 6
    static let linescoreTotalsLeading: CGFloat = 4
    static let linescoreDividerWidth: CGFloat = 0.5
    static let linescoreDividerVerticalPadding: CGFloat = 3
    static let linescoreCornerRadius: CGFloat = 6

    // MARK: Game row body (KBOExpandedView)
    static let bodyOuterSpacing: CGFloat = 6
    static let bodyOuterHorizontalPadding: CGFloat = 14
    static let bodyOuterVerticalPadding: CGFloat = 8

    static let rowGap: CGFloat = 4
    static let rowChildSpacing: CGFloat = 10
    static let rowHorizontalPadding: CGFloat = 10
    static let rowVerticalPadding: CGFloat = 7
    static let rowCornerRadius: CGFloat = 9
    static let rowStrokeActive: CGFloat = 1.2
    static let rowStrokeIdle: CGFloat = 0.5

    static let teamLogoSize: CGFloat = 22
    static let teamSideSpacing: CGFloat = 6
    static let scoreSpacing: CGFloat = 6
    static let liveDotSpacing: CGFloat = 4
    static let livePulseDotSize: CGFloat = 6

    // MARK: Header / day-nav / empty / sizing-formula constants
    static let headerSpacing: CGFloat = 8
    static let headerDayNavSpacing: CGFloat = 4
    static let headerChevronSize: CGFloat = 18
    static let headerDateMinWidth: CGFloat = 80

    static let emptyStateSpacing: CGFloat = 6
    static let emptyStateMinHeight: CGFloat = 100

    static let panelHeaderHeight: CGFloat = 24
    static let panelOuterVerticalPadding: CGFloat = 16   // .padding(.vertical, 8) ×2
    static let panelHeightRowHeight: CGFloat = 50
    static let panelHeightLinescoreSection: CGFloat = 110
    static let panelHeightEmptyExtra: CGFloat = 60
    static let panelHeightFooterSlack: CGFloat = 6

    // MARK: Sizing range scales
    static let panelMinScale: CGFloat = 0.8
    static let panelMaxHeightScale: CGFloat = 1.5

    // MARK: Live state — wing form
    static let liveWingHStackSpacing: CGFloat = 6
    static let liveWingDiamondSize: CGFloat = 22
    static let liveWingCountVerticalSpacing: CGFloat = 1
    static let liveWingCountRowSpacing: CGFloat = 3
    static let liveWingDotSpacing: CGFloat = 2
    static let liveWingDotSize: CGFloat = 6
    static let liveWingPlayerRowSpacing: CGFloat = 3
    static let liveWingHorizontalPadding: CGFloat = 8
    static let liveWingVerticalPadding: CGFloat = 4

    // MARK: Live state — compact (in-row)
    static let liveCompactHStackSpacing: CGFloat = 5
    static let liveCompactDiamondSize: CGFloat = 18
    static let liveCompactDotSpacing: CGFloat = 2
    static let liveCompactDotSize: CGFloat = 6

    /// BasesDiamond inner base size relative to its container's smaller dim.
    /// Pixel-equivalent: at 22pt diamond → ~7.5pt base; at 18pt → ~6pt.
    static let baseDiamondInnerScale: CGFloat = 0.34

    // MARK: Compact wing
    static let compactRowSpacing: CGFloat = 8
    static let compactInnerVerticalSpacing: CGFloat = 1
    static let compactLiveBadgeSpacing: CGFloat = 3
    static let compactLiveDotSize: CGFloat = 5
    static let compactScoreSpacing: CGFloat = 3
    static let compactToggleSpacing: CGFloat = 6
    static let compactToggleWidth: CGFloat = 28
    static let compactToggleHeight: CGFloat = 22
    static let compactToggleCornerRadius: CGFloat = 6
    static let compactHorizontalPadding: CGFloat = 6
    static let compactVerticalPadding: CGFloat = 3
    static let compactBackgroundCornerRadius: CGFloat = 6
    static let compactBackgroundHorizontalInset: CGFloat = 4
    static let compactBackgroundVerticalInset: CGFloat = 2
}
