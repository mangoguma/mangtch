#!/usr/bin/env swift

import AppKit

// Simple test to check notch detection
NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.activate(ignoringOtherApps: true)

// Wait a moment for WindowServer connection
Thread.sleep(forTimeInterval: 0.5)

if let screen = NSScreen.main {
    print("Screen frame: \(screen.frame)")
    print("Safe area insets: \(screen.safeAreaInsets)")
    print("Auxiliary top left: \(screen.auxiliaryTopLeftArea ?? .zero)")
    print("Auxiliary top right: \(screen.auxiliaryTopRightArea ?? .zero)")

    // Check all screens
    print("\nAll screens:")
    for (index, s) in NSScreen.screens.enumerated() {
        print("Screen \(index): safeAreaInsets.top = \(s.safeAreaInsets.top)")
    }
} else {
    print("ERROR: NSScreen.main is nil")
}
