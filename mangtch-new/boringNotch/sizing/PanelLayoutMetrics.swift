import SwiftUI

/// Single panel-sizing resolver. Pure, state-driven — no side effects.
///
/// `.open` snaps to boring.notch's pixel-design canvas (640×190 + chrome) and
/// intentionally ignores the widget; expanded views are pixel-laid against
/// that fixed canvas, so honoring per-widget widths there causes overflow.
/// `.closed` honors the widget's `widthRange.ideal` so compact wings size to
/// their content (long song titles, dynamic KBO rows).
struct PanelLayoutMetrics {
    let closedWidth: CGFloat       // notch + wing*2 (closed state)
    let openWidth: CGFloat         // canvas-fixed
    let wingWidth: CGFloat         // 현재 state 기준
    let panelWidth: CGFloat        // 현재 state 기준 (closedWidth or openWidth)
    let contentHeight: CGFloat     // 위젯 콘텐츠 영역 (chrome 제외)
    let chromeHeight: CGFloat
    var totalHeight: CGFloat { contentHeight + chromeHeight }

    @MainActor
    static func resolve(widget: (any NotchWidget)?,
                        notchSize: CGSize,
                        state: NotchState) -> PanelLayoutMetrics {
        // Open: canvas snap (widget intentionally ignored)
        let openWingW = clamp((LayoutTokens.openCanvasWidth - notchSize.width) / 2,
                              min: LayoutTokens.minWingWidth,
                              max: LayoutTokens.absoluteMaxWingWidth)
        let openContentH = LayoutTokens.openCanvasHeight

        // Closed: widget-driven
        let range = widget?.widthRange ?? .default
        let closedWingW = clamp((range.ideal - notchSize.width) / 2,
                                min: LayoutTokens.minWingWidth,
                                max: LayoutTokens.absoluteMaxWingWidth)
        let closedContentH = widget?.heightRange.ideal ?? HeightRange.default.ideal

        let isOpen = (state == .open)
        return PanelLayoutMetrics(
            closedWidth: notchSize.width + closedWingW * 2,
            openWidth: notchSize.width + openWingW * 2,
            wingWidth: isOpen ? openWingW : closedWingW,
            panelWidth: notchSize.width + (isOpen ? openWingW : closedWingW) * 2,
            contentHeight: isOpen ? openContentH : closedContentH,
            chromeHeight: LayoutTokens.chromeTopHeight
        )
    }

    @MainActor
    static func resolve(widget: AnyNotchWidget?,
                        notchSize: CGSize,
                        state: NotchState) -> PanelLayoutMetrics {
        // Open: canvas snap (widget intentionally ignored)
        let openWingW = clamp((LayoutTokens.openCanvasWidth - notchSize.width) / 2,
                              min: LayoutTokens.minWingWidth,
                              max: LayoutTokens.absoluteMaxWingWidth)
        let openContentH = LayoutTokens.openCanvasHeight

        let range = widget?.widthRange ?? .default
        let closedWingW = clamp((range.ideal - notchSize.width) / 2,
                                min: LayoutTokens.minWingWidth,
                                max: LayoutTokens.absoluteMaxWingWidth)
        let closedContentH = widget?.heightRange.ideal ?? HeightRange.default.ideal

        let isOpen = (state == .open)
        return PanelLayoutMetrics(
            closedWidth: notchSize.width + closedWingW * 2,
            openWidth: notchSize.width + openWingW * 2,
            wingWidth: isOpen ? openWingW : closedWingW,
            panelWidth: notchSize.width + (isOpen ? openWingW : closedWingW) * 2,
            contentHeight: isOpen ? openContentH : closedContentH,
            chromeHeight: LayoutTokens.chromeTopHeight
        )
    }

    private static func clamp(_ x: CGFloat, min lo: CGFloat, max hi: CGFloat) -> CGFloat {
        Swift.min(Swift.max(x, lo), hi)
    }
}
