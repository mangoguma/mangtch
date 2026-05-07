import SwiftUI

/// Single panel-sizing resolver. Pure, state-driven — no side effects.
///
/// Width and height are content-driven for both `.closed` and `.open`: the
/// active widget's `widthRange.ideal` / `heightRange.ideal` are clamped into
/// `[min, max]`. Music widgets opt into a fixed canvas via
/// `WidthRange.fixed(_)` (see `MusicLayoutTokens`).
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

        let panelW = clamp(widthR.ideal, min: widthR.min, max: widthR.max)
        let wingW = clamp((panelW - notchSize.width) / 2,
                          min: LayoutTokens.minWingWidth,
                          max: LayoutTokens.absoluteMaxWingWidth)
        let contentH = clamp(heightR.ideal, min: heightR.min, max: heightR.max)

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
