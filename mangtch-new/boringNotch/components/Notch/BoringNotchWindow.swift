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

    /// Resize the panel window to fit the active widget's metrics, anchored
    /// to the top edge so the notch strip stays glued to the menu bar.
    ///
    /// Width is locked to `LayoutTokens.panelMaxWidth` — the window stays
    /// large enough to host any widget's panel and the actual wing/panel
    /// width animation happens in SwiftUI (`.frame(width: m.wingWidth)`).
    /// Mixing window-frame width animation with SwiftUI's wing-width
    /// animation produced a "fills from the outside" wobble because the
    /// two timing curves drift; locking width sidesteps that entirely.
    /// Height does grow / shrink with content because KBO can exceed the
    /// Music canvas (190pt) — there SwiftUI alone can't fix it without
    /// the NSPanel growing.
    @MainActor
    func resizeWindow(metrics: PanelLayoutMetrics,
                      notchHeight: CGFloat,
                      isOpen: Bool,
                      animated: Bool = true) {
        let height: CGFloat = isOpen
            ? notchHeight + metrics.totalHeight + LayoutTokens.shadowPadding
            : notchHeight + LayoutTokens.shadowPadding
        let width: CGFloat = LayoutTokens.panelMaxWidth

        let anchorScreen = self.screen ?? NSScreen.main
        guard let screenFrame = anchorScreen?.frame else { return }
        let topY = screenFrame.maxY
        let originX = screenFrame.midX - width / 2
        let originY = topY - height
        let newFrame = NSRect(x: originX, y: originY, width: width, height: height)

        // Skip the no-op case so a flurry of identical metrics doesn't keep
        // restarting the implicit animation context.
        if NSEqualRects(self.frame, newFrame) { return }

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.allowsImplicitAnimation = true
                self.animator().setFrame(newFrame, display: true)
            }
        } else {
            self.setFrame(newFrame, display: true)
        }
    }
}
