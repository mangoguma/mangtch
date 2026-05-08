//
//  sizeMatters.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 05/08/24.
//

import Defaults
import Foundation
import SwiftUI

let downloadSneakSize: CGSize = .init(width: 65, height: 1)
let batterySneakSize: CGSize = .init(width: 160, height: 1)

let shadowPadding: CGFloat = LayoutTokens.shadowPadding
/// Initial-window-sizing canvas. Mirrors the Music widget's pixel-design
/// frame because the NSPanel must boot large enough to host any widget
/// before metrics are known; once a widget is active, `PanelLayoutMetrics`
/// drives the actual content frame and (in 5b) the window itself.
let openNotchSize: CGSize = .init(width: MusicLayoutTokens.expandedWidth,
                                  height: MusicLayoutTokens.expandedHeight)
/// Chrome above the widget content area inside the expanded panel —
/// `Divider` (1pt) + `WidgetSwitcherBar` (22pt button + 3pt vertical
/// padding × 2 = 28pt). Read by both `BoringViewModel.panelHeight` and
/// `windowFrame(for:)` so the NSPanel window grows with the chrome.
let expandedChromeTopHeight: CGFloat = LayoutTokens.chromeTopHeight

/// Window size assuming a zero-height notch strip (notched-display
/// fallback). Concrete window creation should use `windowFrame(for:)`
/// to size against the actual `closedNotchSize.height` on the target
/// screen — this constant exists only for compatibility with code
/// paths that need a static size before a screen is known.
let windowSize: CGSize = .init(width: openNotchSize.width,
                               height: openNotchSize.height
                                       + shadowPadding
                                       + expandedChromeTopHeight)

/// Initial NSPanel frame, used at window creation before any
/// `PanelLayoutMetrics` has been published. Sized against the
/// `openNotchSize` canvas so Music (the default widget) renders correctly
/// on first launch; subsequent metrics changes re-frame the window via
/// `BoringNotchWindow.resizeWindow(metrics:notchHeight:isOpen:animated:)`.
@MainActor func initialWindowFrame(for screenUUID: String? = nil) -> CGSize {
    let notchHeight = getClosedNotchSize(screenUUID: screenUUID).height
    return .init(width: openNotchSize.width,
                 height: notchHeight
                         + openNotchSize.height
                         + expandedChromeTopHeight
                         + shadowPadding)
}
let cornerRadiusInsets: (opened: (top: CGFloat, bottom: CGFloat), closed: (top: CGFloat, bottom: CGFloat)) = (opened: (top: 19, bottom: 24), closed: (top: 6, bottom: 14))

enum MusicPlayerImageSizes {
    static let cornerRadiusInset: (opened: CGFloat, closed: CGFloat) = (opened: 13.0, closed: 4.0)
    static let size = (opened: CGSize(width: 90, height: 90), closed: CGSize(width: 20, height: 20))
}

@MainActor func getScreenFrame(_ screenUUID: String? = nil) -> CGRect? {
    var selectedScreen = NSScreen.main

    if let uuid = screenUUID {
        selectedScreen = NSScreen.screen(withUUID: uuid)
    }
    
    if let screen = selectedScreen {
        return screen.frame
    }
    
    return nil
}

@MainActor func getClosedNotchSize(screenUUID: String? = nil) -> CGSize {
    // Default notch size, to avoid using optionals
    var notchHeight: CGFloat = Defaults[.nonNotchHeight]
    var notchWidth: CGFloat = 185

    var selectedScreen = NSScreen.main

    if let uuid = screenUUID {
        selectedScreen = NSScreen.screen(withUUID: uuid)
    }

    // Check if the screen is available
    if let screen = selectedScreen {
        // Only derive notchWidth from auxiliary areas on displays that
        // actually have a notch — on non-notch screens the auxiliary areas
        // can be nil or zero-width, which collapses notchWidth to the full
        // screen width and ruins wing/panel layout.
        if screen.safeAreaInsets.top > 0,
           let topLeftNotchpadding: CGFloat = screen.auxiliaryTopLeftArea?.width,
           let topRightNotchpadding: CGFloat = screen.auxiliaryTopRightArea?.width
        {
            notchWidth = screen.frame.width - topLeftNotchpadding - topRightNotchpadding + 4
        }

        // Check if the Mac has a notch
        if screen.safeAreaInsets.top > 0 {
            // This is a display WITH a notch - use notch height settings
            notchHeight = Defaults[.notchHeight]
            if Defaults[.notchHeightMode] == .matchRealNotchSize {
                notchHeight = screen.safeAreaInsets.top
            } else if Defaults[.notchHeightMode] == .matchMenuBar {
                notchHeight = screen.frame.maxY - screen.visibleFrame.maxY
            }
        } else {
            // This is a display WITHOUT a notch - use non-notch height settings
            notchHeight = Defaults[.nonNotchHeight]
            if Defaults[.nonNotchHeightMode] == .matchMenuBar {
                notchHeight = screen.frame.maxY - screen.visibleFrame.maxY
            }
        }
    }

    return .init(width: notchWidth, height: notchHeight)
}
