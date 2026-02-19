import AppKit
import Carbon.HIToolbox

@MainActor
final class ShortcutManager {
    static let shared = ShortcutManager()

    private var eventHandler: Any?
    private(set) var currentShortcut: KeyboardShortcut = .default

    struct KeyboardShortcut: Equatable {
        let keyCode: UInt16
        let modifiers: NSEvent.ModifierFlags

        static let `default` = KeyboardShortcut(
            keyCode: UInt16(kVK_ANSI_N),
            modifiers: [.command, .shift]
        )

        var displayString: String {
            var parts: [String] = []
            if modifiers.contains(.command) { parts.append("⌘") }
            if modifiers.contains(.shift) { parts.append("⇧") }
            if modifiers.contains(.option) { parts.append("⌥") }
            if modifiers.contains(.control) { parts.append("⌃") }

            // Map common key codes to readable strings
            let keyString: String
            switch Int(keyCode) {
            case kVK_ANSI_N: keyString = "N"
            case kVK_ANSI_M: keyString = "M"
            case kVK_ANSI_P: keyString = "P"
            case kVK_Space: keyString = "Space"
            case kVK_Return: keyString = "Return"
            case kVK_Escape: keyString = "Esc"
            default: keyString = "?"
            }

            parts.append(keyString)
            return parts.joined()
        }
    }

    private init() {}

    func setup() {
        registerGlobalShortcut(currentShortcut)
    }

    func teardown() {
        if let handler = eventHandler {
            NSEvent.removeMonitor(handler)
            eventHandler = nil
        }
    }

    private func registerGlobalShortcut(_ shortcut: KeyboardShortcut) {
        // Remove existing handler
        if let handler = eventHandler {
            NSEvent.removeMonitor(handler)
        }

        // Register new global hotkey
        eventHandler = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return }

            // Check if event matches our shortcut
            if event.keyCode == shortcut.keyCode,
               event.modifierFlags.intersection(.deviceIndependentFlagsMask) == shortcut.modifiers {
                Task { @MainActor in
                    self.handleShortcutTriggered()
                }
            }
        }
    }

    private func handleShortcutTriggered() {
        NotchViewModel.shared.toggleExpand()
    }

    // Future: Method to customize shortcut
    func setCustomShortcut(_ shortcut: KeyboardShortcut) {
        currentShortcut = shortcut
        registerGlobalShortcut(shortcut)
    }
}
