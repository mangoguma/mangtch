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

    // MARK: - Content-driven resize

    /// Grow the panel window's envelope to fit the active widget's open
    /// metrics, anchored to the top edge. Window only ever grows within
    /// a session — never shrinks.
    ///
    /// Upstream boring.notch keeps the NSPanel at a fixed envelope and
    /// renders every visible transition inside the transparent panel via
    /// SwiftUI. We do the same: SwiftUI's centered `.frame(width:)` +
    /// `.frame(maxWidth: .infinity, alignment: .center)` produces a
    /// symmetric expand/collapse purely from layout.
    ///
    /// Shrinking the window — even instantly — produces a visible artifact:
    /// SwiftUI sees the new `notchState` before the deferred `setFrame`
    /// fires (Combine `.receive(on: RunLoop.main)` + `Task { @MainActor }`
    /// adds 1–2 runloop turns), so it re-centers content against the *old*
    /// host bounds for one frame, then jumps after the resize lands. That
    /// reads as "expanding from the top-left." Holding the envelope at the
    /// maximum width/height seen so far avoids all of it.
    @MainActor
    func resizeWindow(metrics: PanelLayoutMetrics,
                      notchHeight: CGFloat,
                      isOpen: Bool,
                      animated: Bool = true) {
        let openHeight = notchHeight + metrics.totalHeight + LayoutTokens.shadowPadding
        let targetWidth = metrics.panelWidth

        let anchorScreen = self.screen ?? NSScreen.main
        guard let screenFrame = anchorScreen?.frame else { return }

        let envelopeWidth = max(self.frame.width, targetWidth)
        let envelopeHeight = max(self.frame.height, openHeight)

        let originX = screenFrame.midX - envelopeWidth / 2
        let originY = screenFrame.maxY - envelopeHeight
        let newFrame = NSRect(x: originX, y: originY,
                              width: envelopeWidth, height: envelopeHeight)

        if NSEqualRects(self.frame, newFrame) { return }
        self.setFrame(newFrame, display: true)
    }
}
