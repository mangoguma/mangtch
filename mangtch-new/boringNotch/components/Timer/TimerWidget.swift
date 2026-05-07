import SwiftUI

@MainActor
final class TimerWidget: NotchWidget {
    let id = "timer"
    let displayName = "Timer"
    let icon = "timer"
    let preferredPosition: WidgetPosition = .leftWing
    var isEnabled: Bool = true

    let viewModel = TimerViewModel()

    /// Static — Timer's compact wing is small (digit + small icon) and
    /// expanded view fits in a fixed 360x260 box (toggle + 90pt dial +
    /// numpad row).
    /// Width is locked to the global panel canvas so switching widgets
    /// never changes wing geometry — the asymmetric compact-view swap
    /// (Music album art ↔ Timer digits ↔ KBO icon) would otherwise show
    /// up as a wobble in the wing frame. Timer's expanded view fits well
    /// inside the panel canvas.
    var widthRange: WidthRange { .fixed(LayoutTokens.panelMaxWidth) }
    var heightRange: HeightRange {
        HeightRange(min: TimerLayoutTokens.panelMinHeight,
                    ideal: TimerLayoutTokens.panelIdealHeight,
                    max: TimerLayoutTokens.panelMaxHeight)
    }

    @MainActor
    func makeCompactView() -> AnyView {
        AnyView(TimerCompactView(viewModel: viewModel))
    }

    @MainActor
    func makeExpandedView() -> AnyView {
        AnyView(TimerExpandedView(viewModel: viewModel))
    }

    func activate() {}
    func deactivate() {
        // Don't reset timer on deactivate — user might want it running
    }
}
