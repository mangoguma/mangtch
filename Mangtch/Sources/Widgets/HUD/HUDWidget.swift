import SwiftUI

@MainActor
final class HUDWidget: NotchWidget {
    let id = "hud"
    let displayName = "System HUD"
    let icon = "speaker.wave.2"
    let preferredPosition: WidgetPosition = .center
    var isEnabled: Bool = true

    private let viewModel = HUDViewModel()

    @MainActor
    func makeCompactView() -> AnyView {
        AnyView(
            Group {
                if viewModel.isVisible {
                    HUDSliderView(
                        type: viewModel.hudType,
                        value: viewModel.value,
                        iconName: viewModel.iconName
                    )
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
        )
    }

    @MainActor
    func makeExpandedView() -> AnyView {
        // HUD doesn't have an expanded state
        AnyView(EmptyView())
    }

    func activate() {
        Task { @MainActor in
            viewModel.startObserving()
        }
    }

    func deactivate() {
        Task { @MainActor in
            viewModel.stopObserving()
        }
    }
}
