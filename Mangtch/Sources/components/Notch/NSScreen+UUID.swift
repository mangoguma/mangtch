import AppKit

extension NSScreen {
    /// Stable per-display identifier from CoreGraphics. Survives reboots and
    /// distinguishes two physically identical monitors that share a
    /// `localizedName`. Returns nil only for fully detached screens.
    var displayUUID: String? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        let cgID = CGDirectDisplayID(number.uint32Value)
        guard let cf = CGDisplayCreateUUIDFromDisplayID(cgID)?.takeRetainedValue() else {
            return nil
        }
        return CFUUIDCreateString(nil, cf) as String
    }
}
