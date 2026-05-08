import SwiftUI
import AppKit

/// Host `BoringNotchWindow` for the current SwiftUI subtree. Injected at the
/// top of each panel's content view so wing-hit-zone reporters can pick
/// the *right* window for screen-coordinate conversion in multi-display setups.
private struct NotchHostWindowKey: EnvironmentKey {
    static let defaultValue: NSWindow? = nil
}

extension EnvironmentValues {
    var notchHostWindow: NSWindow? {
        get { self[NotchHostWindowKey.self] }
        set { self[NotchHostWindowKey.self] = newValue }
    }
}

/// Whether `.wingHitZone(...)` modifiers under this subtree should publish
/// their rects. The wing host stable-mounts every widget's wing tree and
/// flips this per branch so only the active owner's hit zones reach the
/// gesture handler — invisible-but-mounted trees stay silent. Default true
/// so isolated previews and one-off mounts still report.
private struct WingHitZoneEmissionKey: EnvironmentKey {
    static let defaultValue: Bool = true
}

extension EnvironmentValues {
    var wingHitZoneEmissionEnabled: Bool {
        get { self[WingHitZoneEmissionKey.self] }
        set { self[WingHitZoneEmissionKey.self] = newValue }
    }
}

/// Identifies a clickable region that lives on the notch's wings.
/// GestureHandler hit-tests global mouseDown events against the collected
/// rects rather than computing button positions arithmetically.
enum WingButton: String, CaseIterable {
    case musicPrev
    case musicPlayPause
    case musicNext
    case kboTickerToggle
    case kboTTSToggle
    case kboSoundToggle
}

struct WingHitZone: Equatable {
    let button: WingButton
    /// Frame of the button in **screen coordinates** (AppKit bottom-left origin).
    let rect: CGRect
}

struct WingHitZonesKey: PreferenceKey {
    static let defaultValue: [WingHitZone] = []
    static func reduce(value: inout [WingHitZone], nextValue: () -> [WingHitZone]) {
        value.append(contentsOf: nextValue())
    }
}

private struct WingHitZoneReporter: ViewModifier {
    let button: WingButton
    @Environment(\.notchHostWindow) private var hostWindow
    @Environment(\.wingHitZoneEmissionEnabled) private var emissionEnabled

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { proxy in
                let global = proxy.frame(in: .global)
                let screenRect = toScreen(rect: global)
                Color.clear.preference(
                    key: WingHitZonesKey.self,
                    value: emissionEnabled
                        ? [WingHitZone(button: button, rect: screenRect)]
                        : []
                )
            }
        )
    }

    /// SwiftUI `.global` is the host window's content-view coordinate
    /// space (origin top-left, y growing down); AppKit window/screen y
    /// goes UP from the bottom-left. Flip inside the window first, then
    /// hand the window-coord rect to `convertToScreen`.
    @MainActor
    private func toScreen(rect: CGRect) -> CGRect {
        guard let window = hostWindow else {
            // No injected window — return rect as-is (fallback for previews).
            return rect
        }
        let flippedY = window.frame.height - rect.minY - rect.height
        let inWindow = CGRect(x: rect.minX, y: flippedY,
                              width: rect.width, height: rect.height)
        return window.convertToScreen(inWindow)
    }
}

extension View {
    /// Register this view as a wing hit zone. GestureHandler picks up
    /// global mouseDown events that fall inside the resulting screen rect
    /// and dispatches the matching action.
    func wingHitZone(_ button: WingButton) -> some View {
        modifier(WingHitZoneReporter(button: button))
    }
}
