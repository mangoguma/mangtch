import SwiftUI

@MainActor
final class DownloadWidget: NotchWidget {
    let id = "downloads"
    let displayName = "Downloads"
    let icon = "arrow.down.circle"
    let preferredPosition: WidgetPosition = .leftWing
    var isEnabled: Bool = true

    let viewModel = DownloadViewModel()

    @MainActor
    func makeCompactView() -> AnyView {
        AnyView(DownloadCompactView(viewModel: viewModel))
    }

    @MainActor
    func makeExpandedView() -> AnyView {
        AnyView(DownloadExpandedView(viewModel: viewModel))
    }

    func activate() {
        Task { @MainActor in
            viewModel.startMonitoring()
        }
    }

    func deactivate() {
        Task { @MainActor in
            viewModel.stopMonitoring()
        }
    }
}
