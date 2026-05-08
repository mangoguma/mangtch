//
//  NotchSpaceManager.swift
//  boringNotch
//
//  Created by Alexander on 2024-10-27.
//

import AppKit

class NotchSpaceManager {
    static let shared = NotchSpaceManager()

    /// Tracks windows managed by the notch panel (replaces the removed CGSSpace).
    var notchSpace: NotchWindowSet = .init()

    private init() {}
}

/// Minimal stand-in for the removed CGSSpace type.
struct NotchWindowSet {
    var windows: Set<NSWindow> = []
}
