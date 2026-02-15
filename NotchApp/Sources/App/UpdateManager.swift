import Foundation
import Sparkle

/// Manages Sparkle auto-update functionality.
@MainActor
final class UpdateManager: NSObject, ObservableObject {
    static let shared = UpdateManager()

    private let updaterController: SPUStandardUpdaterController

    /// The underlying Sparkle updater for direct configuration.
    var updater: SPUUpdater {
        updaterController.updater
    }

    /// Whether the "Check for Updates" action is currently available.
    @Published var canCheckForUpdates = false

    private override init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
    }

    /// Start the updater. Call once during app launch.
    func start() {
        // Sync Sparkle's setting with our SettingsManager
        updater.automaticallyChecksForUpdates = SettingsManager.shared.automaticallyCheckForUpdates

        updaterController.startUpdater()

        // Observe canCheckForUpdates via KVO
        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canCheckForUpdates)
    }

    /// Manually check for updates (triggered by menu item or settings button).
    func checkForUpdates() {
        updater.checkForUpdates()
    }
}
