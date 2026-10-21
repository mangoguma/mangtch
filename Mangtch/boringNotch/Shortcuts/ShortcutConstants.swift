//
//  Constants.swift
//  boringNotch
//
//  Created by Richard Kunkli on 16/08/2024.
//

import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    static let clipboardHistoryPanel = Self("clipboardHistoryPanel")
    /// Not user-configurable: only enabled while clipboard cards are
    /// selected (see `ClipboardView`), disabled the rest of the time.
    static let clipboardCopySelection = Self("clipboardCopySelection", default: .init(.c, modifiers: [.command]))
    static let toggleMicrophone = Self("toggleMicrophone", default: .init(.f5, modifiers: [.function]))
    static let decreaseBacklight = Self("decreaseBacklight", default: .init(.f1, modifiers: [.command]))
    static let increaseBacklight = Self("increaseBacklight", default: .init(.f2, modifiers: [.command]))
    static let toggleSneakPeek = Self("toggleSneakPeek", default: .init(.h, modifiers: [.command, .shift]))
    static let toggleNotchOpen = Self("toggleNotchOpen", default: .init(.i, modifiers: [.command, .shift]))
    static let toggleNotchHidden = Self("toggleNotchHidden", default: .init(.b, modifiers: [.command, .shift]))
    static let toggleMenuBarItems = Self("toggleMenuBarItems")
}
