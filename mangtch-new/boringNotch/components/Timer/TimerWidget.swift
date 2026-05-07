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
    var preferredPanelWidth: CGFloat? { 480 }
    var preferredPanelHeight: CGFloat? { 260 }

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
