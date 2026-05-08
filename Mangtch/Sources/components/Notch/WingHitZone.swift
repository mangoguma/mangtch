import SwiftUI
import AppKit

/// Host `NotchWindow` for the current SwiftUI subtree. Injected at the
/// top of each panel's content view so wing-hit-zone reporters can pick
/// the *right* window for screen-coordinate conversion in multi-display
/// setups (the `NotchWindow.shared` accessor only sees the primary).
private struct NotchHostWindowKey: EnvironmentKey {
    static let defaultValue: NotchWindow? = nil
}

extension EnvironmentValues {
    var notchHostWindow: NotchWindow? {
        get { self[NotchHostWindowKey.self] }
        set { self[NotchHostWindowKey.self] = newValue }
    }
}

/// Identifies a clickable region that lives on the notch's wings. Each
/// wing button (music transport, KBO toggles, etc.) registers itself
/// with one of these via the `.wingHitZone(_:)` modifier; GestureHandler
/// hit-tests global mouseDown events against the collected rects rather
/// than computing button positions arithmetically — so the buttons keep
/// working when wing widths or layouts change.
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
    /// Frame of the button in **screen coordinates** (origin top-left
    /// flipped to AppKit's bottom-left at read time). The view modifier
    /// reads `proxy.frame(in: .global)` and converts.
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

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { proxy in
                let global = proxy.frame(in: .global)
                let screenRect = toScreen(rect: global)
                Color.clear.preference(
                    key: WingHitZonesKey.self,
                    value: [WingHitZone(button: button, rect: screenRect)]
                )
            }
        )
    }

    /// SwiftUI `.global` is the host window's content-view coordinate
    /// space (origin top-left, y growing down); AppKit window/screen y
    /// goes UP from the bottom-left. Flip inside the window first, then
    /// hand the window-coord rect to `convertToScreen` (which also
    /// applies the host's screen origin offset).
    @MainActor
    private func toScreen(rect: CGRect) -> CGRect {
        // Fall back to the primary if env injection somehow missed —
        // single-display setups still resolve correctly that way.
        let window = hostWindow ?? NotchWindow.shared
        let flippedY = window.frame.height - rect.minY - rect.height
        let inWindow = CGRect(x: rect.minX, y: flippedY,
                              width: rect.width, height: rect.height)
        return window.convertToScreen(inWindow)
    }
}

extension View {
    /// Register this view as a wing hit zone. GestureHandler picks up
    /// global mouseDown events that fall inside the resulting screen
    /// rect and dispatches the matching action. The view itself remains
    /// non-interactive (the panel's `.nonactivatingPanel` style swallows
    /// SwiftUI's own click handling).
    func wingHitZone(_ button: WingButton) -> some View {
        modifier(WingHitZoneReporter(button: button))
    }
}
