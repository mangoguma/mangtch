import SwiftUI

/// Layout constants for the Timer widget. Domain-scoped — kept here
/// rather than in global LayoutTokens because these values shape the
/// Timer's visual identity (progress ring proportions, mode pill chrome)
/// and are not reused by other widgets.
enum TimerLayoutTokens {
    // MARK: Widget panel range (TimerWidget.widthRange/heightRange)
    static let panelMinWidth: CGFloat = 360
    static let panelIdealWidth: CGFloat = 480
    static let panelMinHeight: CGFloat = 220
    static let panelIdealHeight: CGFloat = 260
    static let panelMaxHeight: CGFloat = 320

    /// Closed-state panel width — tight enough that the resting wings
    /// don't dominate the menu bar. Each wing only needs a small ring
    /// (compactRingSize 18) on the left and the countdown digits on the
    /// right; matches Music widget's compact target. Opening the panel
    /// snaps to `LayoutTokens.panelMaxWidth` (640) for the timer canvas.
    static let compactWidth: CGFloat = 340
    static let compactMinWidth: CGFloat = 285

    // MARK: Expanded view container
    static let expandedSpacing: CGFloat = 16
    static let expandedHorizontalPadding: CGFloat = 20
    static let expandedVerticalPadding: CGFloat = 12

    // MARK: Mode picker (capsule pill)
    static let modePillHorizontalPadding: CGFloat = 14
    static let modePillVerticalPadding: CGFloat = 5

    // MARK: Time display row
    static let timeDisplaySpacing: CGFloat = 16
    static let progressRingSize: CGFloat = 90
    static let progressRingStroke: CGFloat = 4
    static let adjustButtonSize: CGFloat = 28

    // MARK: Action buttons (Start / Pause / Reset)
    static let actionRowSpacing: CGFloat = 12
    static let actionButtonInternalSpacing: CGFloat = 6
    static let actionButtonHorizontalPadding: CGFloat = 14
    static let actionButtonVerticalPadding: CGFloat = 7

    // MARK: Compact wing
    static let compactRowSpacing: CGFloat = 8
    static let compactRingSize: CGFloat = 18
    static let compactRingStroke: CGFloat = 2.5
    static let compactHorizontalPadding: CGFloat = 6
    static let compactVerticalPadding: CGFloat = 4
}
