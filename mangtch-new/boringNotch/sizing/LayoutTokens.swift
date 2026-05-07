import SwiftUI

/// Single source of truth for panel layout magic numbers.
/// Two categories:
///   - **Canvas constants** — fixed by upstream pixel-design (do NOT change
///     without re-laying out boring.notch's MusicPlayerView/AlbumArtView).
///   - **Policy constants** — design assumptions (changeable, but document
///     the visual intent in the doc-comment).
enum LayoutTokens {
    // MARK: Canvas (boring.notch native pixel-design — locked)
    static let openCanvasWidth: CGFloat = 640
    static let openCanvasHeight: CGFloat = 190
    static let shadowPadding: CGFloat = 20

    /// Divider (1pt) + WidgetSwitcherBar (22pt button + 3pt × 2 padY).
    /// Read by both BoringViewModel.panelHeight and windowFrame(for:).
    static let chromeTopHeight: CGFloat = 29

    // MARK: Wing geometry
    static let wingTopOuterRadius: CGFloat = 8       // boring.notch concave scoop
    static let panelCornerRadius: CGFloat = 14
    static let minWingWidth: CGFloat = 130           // visual floor
    static let absoluteMaxWingWidth: CGFloat = 480

    // MARK: Expanded content insets
    static let panelHorizontalInset: CGFloat = 12
    static let panelBottomInset: CGFloat = 12
    static let dividerHorizontalInset: CGFloat = 20
    static let switcherBarPadY: CGFloat = 3

    // MARK: Visual balance (의존성 토큰 — 같이 움직여야 하는 값들)
    /// AlbumArtView가 만드는 외곽 inset (NotchHomeView.swift:21).
    static let artworkInset: CGFloat = 5
    /// 반대편 보정 — artworkInset과 동일하게 유지되어야 panel이 좌우 대칭.
    /// 앨범아트 padding을 바꾸면 이 값도 자동으로 따라감.
    static var visualBalanceInset: CGFloat { artworkInset }

    // MARK: Music expanded inner layout
    static let musicLyricsGutter: CGFloat = 15

    // MARK: Music compact wing
    static let compactRowSpacing: CGFloat = 10
    static let compactTransportSpacing: CGFloat = 6
    static let compactControlSize: CGFloat = 22
    static let compactHorizontalPadding: CGFloat = 8
}
