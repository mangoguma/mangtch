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
    /// Both width and height track `metrics`. To keep SwiftUI's
    /// `.easeInOut(0.22)` wing/panel-width animation visually synced with
    /// the NSWindow frame animation, we drive `NSAnimationContext` with the
    /// exact bezier control points SwiftUI's `easeInOut` uses
    /// (`(0.42, 0, 0.58, 1.0)`) for the same 0.22s duration. CoreAnimation's
    /// named `.easeInEaseOut` is *almost* the same curve but not identical —
    /// using the explicit control points eliminates the edge-wobble that
    /// killed phase-5b's first attempt at content-driven width.
    @MainActor
    func resizeWindow(metrics: PanelLayoutMetrics,
                      notchHeight: CGFloat,
                      isOpen: Bool,
                      closedBannerHeight: CGFloat = 0,
                      animated: Bool = true) {
        let height: CGFloat = isOpen
            ? notchHeight + metrics.totalHeight + LayoutTokens.shadowPadding
            : notchHeight + closedBannerHeight + LayoutTokens.shadowPadding
        let width: CGFloat = metrics.panelWidth

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
                ctx.timingFunction = CAMediaTimingFunction(
                    controlPoints: 0.42, 0, 0.58, 1.0
                )
                ctx.allowsImplicitAnimation = true
                self.animator().setFrame(newFrame, display: true)
            }
        } else {
            self.setFrame(newFrame, display: true)
        }
    }
}
