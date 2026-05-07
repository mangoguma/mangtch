import SwiftUI

@MainActor
final class TimerWidget: NotchWidget {
    let id = "timer"
    let displayName = "Timer"
    let icon = "timer"
    let preferredPosition: WidgetPosition = .leftWing
    var isEnabled: Bool = true

    let viewModel = TimerViewModel()

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
