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
    var widthRange: WidthRange { WidthRange(min: 360, ideal: 480, max: LayoutTokens.openCanvasWidth) }
    var heightRange: HeightRange { HeightRange(min: 220, ideal: 260, max: 320) }

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
