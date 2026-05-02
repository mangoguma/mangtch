import SwiftUI
import AppKit

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

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { proxy in
                let global = proxy.frame(in: .global)
                // SwiftUI's `.global` is the panel window's coordinate
                // space (origin top-left). Convert to NSScreen coords by
                // adding the window's screen origin and flipping Y.
                let screenRect = Self.toScreen(rect: global)
                Color.clear.preference(
                    key: WingHitZonesKey.self,
                    value: [WingHitZone(button: button, rect: screenRect)]
                )
            }
        )
    }

    /// SwiftUI `.global` is the host window's content-view coordinate
    /// space (origin top-left, y growing down). NotchWindow is centred
    /// horizontally above the screen and only `panelWidth + 40` wide, so
    /// we need its actual frame to get to screen (NSEvent) coordinates.
    /// `convertToScreen` does the AppKit flip + offset for us.
    @MainActor
    private static func toScreen(rect: CGRect) -> CGRect {
        let window = NotchWindow.shared
        // SwiftUI `.global` y is measured from the window's TOP going
        // down; AppKit window/screen y goes UP from the bottom-left.
        // Convert by flipping inside the window first, then handing the
        // window-coord rect to `convertToScreen`.
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
