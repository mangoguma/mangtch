import SwiftUI

/// Single panel-sizing resolver. Pure, state-driven — no side effects.
///
/// Width is state-aware: `.closed` clamps `widthRange.ideal` (the
/// content-driven "compact" width), `.open` clamps `widthRange.max` (the
/// expanded canvas). Widgets that want the same width in both states
/// declare `WidthRange.fixed(_)` so `min == ideal == max` and the clamp
/// degenerates. Height uses `heightRange.ideal` regardless of state — the
/// closed branch ignores `contentHeight` anyway (only `notchSize.height`
/// shows when collapsed).
struct PanelLayoutMetrics: Equatable {
    let panelWidth: CGFloat        // notch + wing*2
    let wingWidth: CGFloat
    let contentHeight: CGFloat     // 위젯 콘텐츠 영역 (chrome 제외)
    let chromeHeight: CGFloat
    var totalHeight: CGFloat { contentHeight + chromeHeight }

    @MainActor
    static func resolve(widget: (any NotchWidget)?,
                        notchSize: CGSize,
                        state: NotchState) -> PanelLayoutMetrics {
        let widthR = widget?.widthRange ?? .default
        let heightR = widget?.heightRange ?? .default

        let widthTarget = state == .open ? widthR.max : widthR.ideal
        let panelW = clamp(widthTarget, min: widthR.min, max: widthR.max)
        let wingW = clamp((panelW - notchSize.width) / 2,
                          min: LayoutTokens.minWingWidth,
                          max: LayoutTokens.absoluteMaxWingWidth)
        // `panelBottomInset` (applied in `ContentView.expandedContent` to the
        // widget Group) is panel-level chrome that the widget's own
        // `heightRange.ideal` doesn't model. Bake it in here so the formula
        // bootstrap matches the rendered intrinsic before measurement
        // settles — without it the outer `.frame(height:)` is short by 12pt
        // on the first frame and the bottom rounded corner gets clipped.
        let contentH = clamp(heightR.ideal, min: heightR.min, max: heightR.max)
            + LayoutTokens.panelBottomInset

        return PanelLayoutMetrics(
            panelWidth: notchSize.width + wingW * 2,
            wingWidth: wingW,
            contentHeight: contentH,
            chromeHeight: LayoutTokens.chromeTopHeight
        )
    }

    /// Convenience for the type-erased wrapper used by `WidgetRegistry`.
    @MainActor
    static func resolve(widget: AnyNotchWidget?,
                        notchSize: CGSize,
                        state: NotchState) -> PanelLayoutMetrics {
        resolve(widget: widget?.wrapped, notchSize: notchSize, state: state)
    }

    private static func clamp(_ x: CGFloat, min lo: CGFloat, max hi: CGFloat) -> CGFloat {
        Swift.min(Swift.max(x, lo), hi)
    }
}
