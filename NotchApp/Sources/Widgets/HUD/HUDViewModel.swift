import SwiftUI
import Combine

@Observable
@MainActor
final class HUDViewModel {
    // MARK: - State
    var isVisible: Bool = false
    var hudType: HUDType = .volume
    var value: Float = 0.0
    var iconName: String = "speaker.wave.2.fill"

    // MARK: - Private
    private var cancellables = Set<AnyCancellable>()
    private var dismissTask: Task<Void, Never>?

    init() {}

    func startObserving() {
        EventBus.shared.hudTriggers
            .sink { [weak self] (type, value) in
                self?.showHUD(type: type, value: value)
            }
            .store(in: &cancellables)
    }

    func stopObserving() {
        cancellables.removeAll()
        dismissTask?.cancel()
    }

    // MARK: - Private

    private func showHUD(type: HUDType, value: Float) {
        self.hudType = type
        self.value = value
        self.iconName = iconForType(type, value: value)

        withAnimation(AnimationTokens.hudAppear) {
            self.isVisible = true
        }

        // Reset dismiss timer
        dismissTask?.cancel()
        dismissTask = Task {
            let delay = SettingsManager.shared.hudAutoHideDelay
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            withAnimation(AnimationTokens.hudDismiss) {
                self.isVisible = false
                NotchViewModel.shared.setHUDHidden()
            }
        }
    }

    private func iconForType(_ type: HUDType, value: Float) -> String {
        switch type {
        case .volume:
            if value <= 0.001 { return "speaker.slash.fill" }
            if value < 0.33 { return "speaker.wave.1.fill" }
            if value < 0.66 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"

        case .brightness:
            if value < 0.5 { return "sun.min.fill" }
            return "sun.max.fill"

        case .keyboardBacklight:
            if value < 0.01 { return "light.min" }
            return "light.max"
        }
    }
}
