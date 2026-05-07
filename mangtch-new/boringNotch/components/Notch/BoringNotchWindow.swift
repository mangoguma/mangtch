//
//  BoringNotchWindow.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 06/08/24.
//

import Cocoa
import Combine
import Defaults

class BoringNotchWindow: NSPanel {
    private var observers: Set<AnyCancellable> = []

    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: backing,
            defer: flag
        )

        isFloatingPanel = true
        isOpaque = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        isMovable = false

        // Force dark appearance regardless of system setting
        appearance = NSAppearance(named: .darkAqua)

        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle,
        ]

        isReleasedWhenClosed = false
        level = .mainMenu + 3
        hasShadow = false

        updateSharingType()
        setupObservers()
    }

    private func setupObservers() {
        Defaults.publisher(.hideFromScreenRecording)
            .sink { [weak self] _ in self?.updateSharingType() }
            .store(in: &observers)
    }

    private func updateSharingType() {
        sharingType = Defaults[.hideFromScreenRecording] ? .none : .readWrite
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
