import Foundation
import Sparkle

/// Manages Sparkle auto-update functionality.
///
/// Sparkle requires a proper `.app` bundle with Info.plist containing
/// CFBundleIdentifier and CFBundleVersion. When running via `swift run`
/// (debug), the updater is silently disabled.
@MainActor
final class UpdateManager: NSObject, ObservableObject {
    static let shared = UpdateManager()

    private var updaterController: SPUStandardUpdaterController?

    /// The underlying Sparkle updater for direct configuration.
    var updater: SPUUpdater? {
        updaterController?.updater
    }

    /// Whether the "Check for Updates" action is currently available.
    @Published var canCheckForUpdates = false

    /// Whether we're running inside a proper .app bundle.
    private let isInAppBundle: Bool

    private override init() {
        // Sparkle needs CFBundleIdentifier — only available inside a .app bundle
        isInAppBundle = Bundle.main.bundleIdentifier != nil
            && Bundle.main.bundlePath.hasSuffix(".app")

        if isInAppBundle {
            updaterController = SPUStandardUpdaterController(
                startingUpdater: false,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
        }
        super.init()
    }

    /// Start the updater. Call once during app launch.
    func start() {
        guard isInAppBundle, let updater = updater else {
            print("[UpdateManager] Not in app bundle — Sparkle disabled")
            return
        }

        // Sync Sparkle's setting with our SettingsManager
        updater.automaticallyChecksForUpdates = SettingsManager.shared.automaticallyCheckForUpdates

        updaterController?.startUpdater()

        // Observe canCheckForUpdates via KVO
        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canCheckForUpdates)
    }

    /// Manually check for updates (triggered by menu item or settings button).
    func checkForUpdates() {
        guard isInAppBundle else {
            print("[UpdateManager] Not in app bundle — cannot check for updates")
            return
        }
        updater?.checkForUpdates()
    }
}
