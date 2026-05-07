//
//  XPCHelperClient.swift
//  boringNotch
//
//  Stub replacing the deleted XPCHelperClient/ directory.
//  XPC-based brightness / accessibility features are no-ops until reimplemented.
//

import Foundation

extension Notification.Name {
    static let accessibilityAuthorizationChanged = Notification.Name("accessibilityAuthorizationChanged")
}

final class XPCHelperClient {
    static let shared = XPCHelperClient()
    private init() {}

    // MARK: - Accessibility (stub)

    func isAccessibilityAuthorized() async -> Bool { false }
    func requestAccessibilityAuthorization() {}
    func ensureAccessibilityAuthorization(promptIfNeeded: Bool) async -> Bool { false }
    func startMonitoringAccessibilityAuthorization() {}
    func stopMonitoringAccessibilityAuthorization() {}

    // MARK: - Screen brightness (stub)

    func currentScreenBrightness() async -> Float? { nil }
    func setScreenBrightness(_ value: Float) async -> Bool { false }

    // MARK: - Keyboard backlight (stub)

    func currentKeyboardBrightness() async -> Float? { nil }
    func setKeyboardBrightness(_ value: Float) async -> Bool { false }
}
