import AppKit
import SwiftUI

/// NSHostingView subclass that accepts first-mouse events. Required because the
/// notch panel uses `.nonactivatingPanel` style — without this override, clicks
/// that land on the panel while it is not the key window are swallowed as
/// activation events and never reach SwiftUI's hit-testing.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
