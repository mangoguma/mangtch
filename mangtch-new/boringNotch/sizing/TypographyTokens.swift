import SwiftUI

/// Semantic typography. Each token names a *role* (compactTitle,
/// expandedHeader, timerDisplay) and resolves to a concrete `Font`. Sizes
/// are pixel-tuned for the notch surface, not Dynamic Type — the panel is
/// a small chrome and large system fonts would break layout. 7d clamps
/// Dynamic Type explicitly if it ever lands.
///
/// Naming axes:
///   - **compact*** — wing chrome, single-line.
///   - **expanded*** — opened panel, multi-line / structured.
///   - **micro/tiny*** — badges and very small labels (8–9pt).
///   - **timer*** / **kbo*** — domain readouts that need rounded/mono digits.
enum TypographyTokens {
    // MARK: Compact wing
    /// Wing track title, KBO compact mode picker label.
    static let compactTitle = Font.system(size: 11, weight: .semibold)
    /// Wing artist line.
    static let compactSubtitle = Font.system(size: 10, weight: .regular)
    /// Wing transport glyphs (play/prev/next).
    static let compactGlyph = Font.system(size: 11, weight: .semibold)
    /// WidgetSwitcherBar tab icons.
    static let switcherIcon = Font.system(size: 12, weight: .medium)

    // MARK: Expanded panel
    /// Section header (KBO header, panel titles).
    static let expandedHeader = Font.system(size: 12, weight: .semibold)
    /// Body text (date pill, mode picker, vs label).
    static let expandedBody = Font.system(size: 11, weight: .medium)
    /// Plain 11pt — error messages, "취소", "·" separator.
    static let expandedBodyPlain = Font.system(size: 11)
    /// 11pt semibold — game row score text, starter name.
    static let expandedBodySemibold = Font.system(size: 11, weight: .semibold)
    /// Caption (10pt plain) — small inline labels.
    static let expandedCaption = Font.system(size: 10)
    /// Caption (12pt plain) — KBO compact mode helper text, jump button.
    static let expandedCaptionLarge = Font.system(size: 12)
    /// 10pt semibold — result badges, status chips, secondary actions.
    static let expandedSemibold = Font.system(size: 10, weight: .semibold)
    /// 10pt bold — emphasis badge ("승"/"패").
    static let expandedSmallBold = Font.system(size: 10, weight: .bold)
    /// 10pt medium — KBO live state inning row.
    static let expandedSmallMedium = Font.system(size: 10, weight: .medium)

    // MARK: Tiny / badge
    /// 8pt bold — very small badges (KBO position badge, micro labels).
    static let microBadge = Font.system(size: 8, weight: .bold)
    /// 8pt bold rounded — KBO live count digits.
    static let microBadgeRounded = Font.system(size: 8, weight: .bold, design: .rounded)
    /// 8pt semibold — Timer compact mode pill text.
    static let microSemibold = Font.system(size: 8, weight: .semibold)
    /// 9pt semibold — KBO "선발" header, live state secondary.
    static let tinyLabel = Font.system(size: 9, weight: .semibold)
    /// 9pt bold — KBO live count summary chip.
    static let tinyLabelBold = Font.system(size: 9, weight: .bold)
    /// 9pt medium — KBO compact starter name.
    static let tinyLabelMedium = Font.system(size: 9, weight: .medium)

    // MARK: KBO domain
    /// Compact wing score number (13pt bold rounded).
    static let kboCompactScore = Font.system(size: 13, weight: .bold, design: .rounded)
    /// Expanded score number (16pt bold rounded).
    static let kboBigScore = Font.system(size: 16, weight: .bold, design: .rounded)
    /// Linescore inning number (rounded, monospaced — applied at site).
    static let kboInningCell = Font.system(size: 11, weight: .semibold, design: .rounded)
    static let kboInningCellTotal = Font.system(size: 11, weight: .bold, design: .rounded)
    static let kboInningCellHeader = Font.system(size: 9, weight: .semibold, design: .rounded)
    /// 20pt plain — empty-state warning glyph in KBO.
    static let kboLargeGlyph = Font.system(size: 20)
    /// 22pt plain — KBO empty-state baseball glyph.
    static let kboHeroGlyph = Font.system(size: 22)
    /// 10pt semibold rounded — KBO live elapsed-time pill.
    static let kboLivePill = Font.system(size: 10, weight: .semibold, design: .rounded)

    // MARK: Timer domain
    /// Expanded timer countdown (22pt bold rounded).
    static let timerDisplay = Font.system(size: 22, weight: .bold, design: .rounded)
    /// Compact wing countdown (12pt semibold rounded).
    static let timerCompact = Font.system(size: 12, weight: .semibold, design: .rounded)
    /// Compact wing label / control glyphs.
    static let timerCompactLabel = Font.system(size: 12, weight: .medium)
    /// Expanded timer ± buttons / control text.
    static let timerControl = Font.system(size: 13, weight: .medium)
    /// Expanded mode pill text, segmented label.
    static let timerLabel = Font.system(size: 11, weight: .semibold)

    // MARK: Lyrics
    static let lyricsBody = Font.system(size: 11)
    static let lyricsPlaceholder = Font.system(size: 10)
}
