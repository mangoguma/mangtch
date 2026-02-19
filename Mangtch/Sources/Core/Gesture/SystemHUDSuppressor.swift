import AppKit
import CoreGraphics

/// Suppresses macOS native HUD for volume and brightness keys.
///
/// Uses two complementary strategies:
/// 1. **OSDUIHelper unload** — Prevents the native OSD overlay from appearing.
/// 2. **CGEventTap (listenOnly)** — Observes system key events WITHOUT consuming them,
///    so macOS still processes volume/brightness changes normally.
///    Detected key events are forwarded to the onKeyEvent callback for HUD display.
@MainActor
final class SystemHUDSuppressor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isOSDHidden = false

    /// Callback when a system key event is detected.
    /// Parameters: keyCode (Int32), isKeyDown (Bool)
    var onKeyEvent: ((Int32, Bool) -> Void)?

    // MARK: - OSD Suppression via launchctl

    private func hideNativeOSD() {
        guard !isOSDHidden else { return }

        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = ["unload", "-wF",
                          "/System/Library/LaunchAgents/com.apple.OSDUIHelper.plist"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
            isOSDHidden = true
            print("[SystemHUDSuppressor] Native OSD hidden (OSDUIHelper unloaded)")
        } catch {
            print("[SystemHUDSuppressor] Failed to hide native OSD: \(error)")
        }
    }

    private func restoreNativeOSD() {
        guard isOSDHidden else { return }

        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = ["load", "-wF",
                          "/System/Library/LaunchAgents/com.apple.OSDUIHelper.plist"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
            isOSDHidden = false
            print("[SystemHUDSuppressor] Native OSD restored (OSDUIHelper reloaded)")
        } catch {
            print("[SystemHUDSuppressor] Failed to restore native OSD: \(error)")
        }
    }

    // MARK: - Event Tap (Listen Only)

    /// Starts observing system key events and optionally hides native OSD.
    /// The event tap uses listenOnly mode — events are NOT consumed,
    /// so macOS processes volume/brightness changes normally.
    @discardableResult
    func start(hideOSD: Bool = false) -> Bool {
        guard eventTap == nil else { return true }

        guard AXIsProcessTrusted() else {
            print("[SystemHUDSuppressor] Accessibility permissions not granted.")
            print("[SystemHUDSuppressor] Please grant Accessibility access in System Settings → Privacy & Security → Accessibility")
            return false
        }

        if hideOSD {
            hideNativeOSD()
        }

        // We need a context pointer to forward events back to this instance.
        // Use a simple wrapper since the callback is a C function.
        let refconPtr = UnsafeMutableRawPointer(Unmanaged.passRetained(KeyEventContext()).toOpaque())

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                // Re-enable the tap
                if let refcon = refcon {
                    let context = Unmanaged<KeyEventContext>.fromOpaque(refcon).takeUnretainedValue()
                    if let tap = context.tapRef {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                }
                return Unmanaged.passUnretained(event)
            }

            // Filter for NSSystemDefined events (rawValue 14)
            guard type.rawValue == 14 else {
                return Unmanaged.passUnretained(event)
            }

            // Extract key data from the CGEvent
            let nsEvent = NSEvent(cgEvent: event)
            guard let ev = nsEvent, ev.subtype.rawValue == 8 else {
                return Unmanaged.passUnretained(event)
            }

            let data1 = ev.data1
            let keyCode = Int32((data1 & 0xFFFF0000) >> 16)
            let keyFlags = data1 & 0x0000FFFF
            let keyState = (keyFlags & 0xFF00) >> 8
            let isKeyDown = keyState == 0x0A

            // Check if this is a key we care about
            let isSuppressible: Bool
            switch keyCode {
            case 0, 1, 7:    // Volume up, down, mute
                isSuppressible = true
            case 2, 3:        // Brightness up, down
                isSuppressible = true
            case 21, 22:      // Keyboard backlight up, down
                isSuppressible = true
            default:
                isSuppressible = false
            }

            if isSuppressible {
                // Forward to main thread for HUD handling
                let kc = keyCode
                let down = isKeyDown
                DispatchQueue.main.async {
                    if let refcon = refcon {
                        let context = Unmanaged<KeyEventContext>.fromOpaque(refcon).takeUnretainedValue()
                        context.handler?(kc, down)
                    }
                }
            }

            // Always pass through — listenOnly mode, never consume
            return Unmanaged.passUnretained(event)
        }

        let eventMask = CGEventMask(1 << 14) // NSSystemDefined

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: refconPtr
        ) else {
            print("[SystemHUDSuppressor] Failed to create event tap.")
            Unmanaged<KeyEventContext>.fromOpaque(refconPtr).release()
            return false
        }

        // Store tap reference in context for re-enable
        let context = Unmanaged<KeyEventContext>.fromOpaque(refconPtr).takeUnretainedValue()
        context.tapRef = tap
        context.handler = { [weak self] keyCode, isKeyDown in
            self?.onKeyEvent?(keyCode, isKeyDown)
        }

        eventTap = tap

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        print("[SystemHUDSuppressor] Event tap started (listenOnly mode)")
        return true
    }

    func stop() {
        guard let tap = eventTap else { return }

        CGEvent.tapEnable(tap: tap, enable: false)

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
        }

        eventTap = nil
        restoreNativeOSD()

        print("[SystemHUDSuppressor] Event tap stopped.")
    }

    deinit {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            }
        }
    }
}

/// Helper class to pass data through the C callback's refcon pointer.
private class KeyEventContext {
    var tapRef: CFMachPort?
    var handler: ((Int32, Bool) -> Void)?
}
