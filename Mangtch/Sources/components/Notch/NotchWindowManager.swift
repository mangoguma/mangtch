import AppKit
import Combine
import Defaults

/// Owns one `NotchWindow` (with its own `NotchViewModel`) per active
/// display. Single-display setups have exactly one (window, vm) pair —
/// behaviour identical to the legacy singleton model. Toggling
/// `showOnAllDisplays` mirrors a panel onto every connected screen.
@MainActor
final class NotchWindowManager {
    static let shared = NotchWindowManager()

    /// Active panels keyed by `NSScreen.displayUUID`.
    private(set) var windows: [String: NotchWindow] = [:]
    private(set) var viewModels: [String: NotchViewModel] = [:]

    /// UUID of the resolver-chosen "primary" panel. External callers
    /// (drag detector, music VM, shortcut handler) target the primary so
    /// their behaviour matches the single-display model.
    private(set) var primaryUUID: String?

    private var cancellables = Set<AnyCancellable>()
    private var didInstallObservers = false

    private init() {}

    /// Reconcile windows against the current display set + user prefs.
    /// Idempotent — safe to call repeatedly on screen-parameter changes
    /// or pref toggles.
    func sync() {
        if !didInstallObservers {
            didInstallObservers = true
            installObservers()
        }

        let target = targetScreens()
        let targetByUUID: [String: NSScreen] = Dictionary(uniqueKeysWithValues:
            target.compactMap { screen in
                screen.displayUUID.map { ($0, screen) }
            }
        )

        // Tear down windows whose displays disappeared or were toggled off.
        for (uuid, window) in windows where targetByUUID[uuid] == nil {
            window.orderOut(nil)
            windows.removeValue(forKey: uuid)
            viewModels.removeValue(forKey: uuid)
        }

        // Spin up windows for newly active displays.
        for (uuid, screen) in targetByUUID where windows[uuid] == nil {
            let vm = NotchViewModel(screen: screen)
            let window = NotchWindow(screen: screen, viewModel: vm)
            viewModels[uuid] = vm
            windows[uuid] = window
            window.setup()
        }

        // Refresh frames on all surviving windows in case the geometry
        // shifted (resolution change without disconnect). Rebind the
        // NSScreen reference first — AppKit replaces NSScreen instances
        // on topology changes, so the cached `attachedScreen` may report
        // a stale `frame` that no longer matches this display.
        for (uuid, window) in windows {
            if let fresh = targetByUUID[uuid] {
                window.rebind(to: fresh)
            }
            window.reposition()
        }

        // Pin the resolver-chosen screen as primary. Falls back to the
        // first surviving entry if the chosen one was just removed.
        let resolver = NotchScreenResolver.activeScreen()?.displayUUID
        primaryUUID = resolver.flatMap { windows[$0] != nil ? $0 : nil }
            ?? windows.keys.first
    }

    /// Look up the panel attached to `screen`. Returns nil for screens
    /// the manager isn't currently mirroring onto.
    func window(for screen: NSScreen) -> NotchWindow? {
        screen.displayUUID.flatMap { windows[$0] }
    }

    /// All currently active view models. Used by global content-state
    /// updates (track-change preview, KBO panel-height growth, drop
    /// surfacing) that should mirror onto every visible panel.
    var allViewModels: [NotchViewModel] {
        Array(viewModels.values)
    }

    /// Convenience: panel for the screen containing the given screen-coord
    /// point, used by the gesture handler to route mouse events to the
    /// correct VM in multi-display mode.
    func window(under point: NSPoint) -> NotchWindow? {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) else {
            return nil
        }
        return window(for: screen)
    }

    /// The canonical primary panel. Force-unwrapped because every external
    /// callsite that touches `.shared` runs after `AppDelegate` has
    /// finished its launch-time `sync()`. If we ever need pre-launch
    /// access we'll add a lazy bootstrap path.
    var primaryViewModel: NotchViewModel {
        if let uuid = primaryUUID, let vm = viewModels[uuid] { return vm }
        // Bootstrap fallback: caller hit `.shared` before `sync()` ran.
        // Build a temporary VM tied to whatever screen we can find so
        // initial wiring doesn't crash. Manager will replace this on the
        // first proper sync.
        let screen = NotchScreenResolver.activeScreen() ?? NSScreen.screens[0]
        let vm = NotchViewModel(screen: screen)
        if let uuid = screen.displayUUID {
            viewModels[uuid] = vm
            primaryUUID = uuid
        }
        return vm
    }

    var primaryWindow: NotchWindow {
        if let uuid = primaryUUID, let window = windows[uuid] { return window }
        // Bootstrap path mirrors `primaryViewModel` so external `.shared`
        // accesses during early launch don't trap.
        let screen = NotchScreenResolver.activeScreen() ?? NSScreen.screens[0]
        let vm = primaryViewModel
        let window = NotchWindow(screen: screen, viewModel: vm)
        if let uuid = screen.displayUUID {
            windows[uuid] = window
            primaryUUID = uuid
        }
        return window
    }

    /// Screens that should host a panel right now.
    private func targetScreens() -> [NSScreen] {
        if Defaults[.showOnAllDisplays] {
            return NSScreen.screens
        }
        return [NotchScreenResolver.activeScreen()].compactMap { $0 }
    }

    private func installObservers() {
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in self?.sync() }
            }
            .store(in: &cancellables)

        Defaults.publisher(.showOnAllDisplays)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in self?.sync() }
            }
            .store(in: &cancellables)

        Defaults.publisher(.notchScreen)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in self?.sync() }
            }
            .store(in: &cancellables)
    }
}
