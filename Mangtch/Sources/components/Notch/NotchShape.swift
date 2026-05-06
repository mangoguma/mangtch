import SwiftUI

// MARK: - Wing Shape (boring-notch style)

/// Half of the boring-notch pill, mirrored per wing. The signature
/// detail is the **concave inset at the top-outer corner**: starting
/// from the screen-edge corner, the boundary curves *inward* toward the
/// wing interior before resuming the side edge — giving the panel its
/// "scooped" top look (`topOuterRadius`). The bottom-outer corner is a
/// regular convex round (`bottomOuterRadius`); inner edges (toward the
/// notch body) are square so adjacent wings + notch body merge flush.
///
/// Cribbed from boring-notch's `NotchShape.swift`
/// (https://github.com/TheBoredTeam/boring.notch — top=6, bottom=14
/// defaults), adapted for Mangtch's separate-wings layout.
struct WingShape: Shape {
    enum Side { case left, right }
    let side: Side
    var bottomOuterRadius: CGFloat
    var topOuterRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(bottomOuterRadius, topOuterRadius) }
        set { bottomOuterRadius = newValue.first; topOuterRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        let br = max(0, min(bottomOuterRadius, min(w, h) / 2))
        let tr = max(0, min(topOuterRadius, min(w, h) / 2))
        switch side {
        case .left:
            // Outer = leading (x=0). Inner = trailing (x=w, notch side).
            // Boring-notch order: start at outer-top corner, curve down
            // into interior (concave), down the inset side, convex
            // bottom-outer, across to the inner edge, up.
            p.move(to: .zero)
            p.addQuadCurve(to: CGPoint(x: tr, y: tr), control: CGPoint(x: tr, y: 0))
            p.addLine(to: CGPoint(x: tr, y: h - br))
            p.addQuadCurve(to: CGPoint(x: tr + br, y: h), control: CGPoint(x: tr, y: h))
            p.addLine(to: CGPoint(x: w, y: h))
            p.addLine(to: CGPoint(x: w, y: 0))
            p.closeSubpath()
        case .right:
            // Mirror.
            p.move(to: CGPoint(x: w, y: 0))
            p.addQuadCurve(to: CGPoint(x: w - tr, y: tr), control: CGPoint(x: w - tr, y: 0))
            p.addLine(to: CGPoint(x: w - tr, y: h - br))
            p.addQuadCurve(to: CGPoint(x: w - tr - br, y: h), control: CGPoint(x: w - tr, y: h))
            p.addLine(to: CGPoint(x: 0, y: h))
            p.addLine(to: CGPoint(x: 0, y: 0))
            p.closeSubpath()
        }
        return p
    }
}

/// Bottom-rounded panel chrome whose top edges sit `outerInset` pixels
/// inside the frame on each side. Pairs with `WingShape`'s
/// boring-notch-style top-outer concave: the wing's outer side runs at
/// `x = outerInset` and we want the panel below to continue down that
/// same line, so `panelWidth` measures the *outer* hull (matching
/// `notchWidth + 2·wingWidth`) but the visible chrome insets to align
/// flush with the wings' visible side edges.
struct ExpandedPanelShape: Shape {
    var outerInset: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(outerInset, bottomRadius) }
        set { outerInset = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        let inset = max(0, min(outerInset, w / 2))
        let br = max(0, min(bottomRadius, min(w / 2 - inset, h)))
        p.move(to: CGPoint(x: inset, y: 0))
        p.addLine(to: CGPoint(x: w - inset, y: 0))
        p.addLine(to: CGPoint(x: w - inset, y: h - br))
        if br > 0 {
            p.addQuadCurve(to: CGPoint(x: w - inset - br, y: h),
                           control: CGPoint(x: w - inset, y: h))
        } else {
            p.addLine(to: CGPoint(x: w - inset, y: h))
        }
        p.addLine(to: CGPoint(x: inset + br, y: h))
        if br > 0 {
            p.addQuadCurve(to: CGPoint(x: inset, y: h - br),
                           control: CGPoint(x: inset, y: h))
        } else {
            p.addLine(to: CGPoint(x: inset, y: h))
        }
        p.closeSubpath()
        return p
    }
}

struct NotchShape: Shape {
    var cornerRadius: CGFloat
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var expandedHeight: CGFloat
    var state: NotchState

    var animatableData: CGFloat {
        get { expandedHeight }
        set { expandedHeight = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midX = rect.midX
        let halfNotch = notchWidth / 2

        switch state {
        case .idle, .hovering:
            // Wings extend from notch sides — top edges flush with screen top (y=0)

            // Left wing: starts at top-left, goes right to notch
            path.move(to: CGPoint(x: rect.minX, y: 0))
            path.addLine(to: CGPoint(x: midX - halfNotch, y: 0))

            // Notch cutout (skip over physical notch)
            path.move(to: CGPoint(x: midX + halfNotch, y: 0))

            // Right wing: goes right to edge, then down
            path.addLine(to: CGPoint(x: rect.maxX, y: 0))
            path.addLine(to: CGPoint(x: rect.maxX, y: notchHeight - cornerRadius))
            path.addArc(
                center: CGPoint(x: rect.maxX - cornerRadius, y: notchHeight - cornerRadius),
                radius: cornerRadius,
                startAngle: .degrees(0),
                endAngle: .degrees(90),
                clockwise: false
            )

            // Bottom of right wing back to notch
            path.addLine(to: CGPoint(x: midX + halfNotch, y: notchHeight))

            // Skip over notch
            path.move(to: CGPoint(x: midX - halfNotch, y: notchHeight))

            // Bottom of left wing
            path.addLine(to: CGPoint(x: rect.minX + cornerRadius, y: notchHeight))
            path.addArc(
                center: CGPoint(x: rect.minX + cornerRadius, y: notchHeight - cornerRadius),
                radius: cornerRadius,
                startAngle: .degrees(90),
                endAngle: .degrees(180),
                clockwise: false
            )
            path.addLine(to: CGPoint(x: rect.minX, y: 0))

        case .expanded:
            // Full panel extending below notch
            let totalHeight = notchHeight + expandedHeight

            // Top edge - left wing area
            path.move(to: CGPoint(x: rect.minX + cornerRadius, y: 0))
            path.addLine(to: CGPoint(x: midX - halfNotch, y: 0))

            // Skip notch
            path.move(to: CGPoint(x: midX + halfNotch, y: 0))
            path.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: 0))

            // Right side down
            path.addArc(
                center: CGPoint(x: rect.maxX - cornerRadius, y: cornerRadius),
                radius: cornerRadius,
                startAngle: .degrees(-90),
                endAngle: .degrees(0),
                clockwise: false
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: totalHeight - cornerRadius))

            // Bottom right corner
            path.addArc(
                center: CGPoint(x: rect.maxX - cornerRadius, y: totalHeight - cornerRadius),
                radius: cornerRadius,
                startAngle: .degrees(0),
                endAngle: .degrees(90),
                clockwise: false
            )

            // Bottom edge
            path.addLine(to: CGPoint(x: rect.minX + cornerRadius, y: totalHeight))

            // Bottom left corner
            path.addArc(
                center: CGPoint(x: rect.minX + cornerRadius, y: totalHeight - cornerRadius),
                radius: cornerRadius,
                startAngle: .degrees(90),
                endAngle: .degrees(180),
                clockwise: false
            )

            // Left side up
            path.addLine(to: CGPoint(x: rect.minX, y: cornerRadius))
            path.addArc(
                center: CGPoint(x: rect.minX + cornerRadius, y: cornerRadius),
                radius: cornerRadius,
                startAngle: .degrees(180),
                endAngle: .degrees(270),
                clockwise: false
            )
        }

        return path
    }
}

// MARK: - Notch Geometry Helper

struct NotchGeometry {
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let screenWidth: CGFloat
    let screenHeight: CGFloat
    let notchMinX: CGFloat
    let notchMaxX: CGFloat
    let hasNotch: Bool
    let isFloatingMode: Bool

    static func detect() -> NotchGeometry {
        // The active screen is whichever the user picked in Settings; by
        // default that's the built-in display (`NSScreen.screens[0]`).
        // We deliberately do *not* use `.main` because focus changes would
        // make the panel jump between displays.
        return detect(for: NotchScreenResolver.activeScreen())
    }

    static func detect(for screenOrNil: NSScreen?) -> NotchGeometry {
        guard let screen = screenOrNil else {
            return NotchGeometry(
                notchWidth: 0, notchHeight: 0,
                screenWidth: 1440, screenHeight: 900,
                notchMinX: 0, notchMaxX: 0,
                hasNotch: false, isFloatingMode: false
            )
        }

        let frame = screen.frame
        let safeTop = screen.safeAreaInsets.top
        let hasNotch = safeTop > 0

        if hasNotch {
            // Calculate notch bounds using auxiliary areas
            let leftArea = screen.auxiliaryTopLeftArea ?? .zero
            let rightArea = screen.auxiliaryTopRightArea ?? .zero

            let notchMinX: CGFloat
            let notchMaxX: CGFloat

            // Sanity range for an actual hardware notch — every shipping
            // notched MacBook is between ~150pt and ~400pt wide. macOS 26
            // (Tahoe) appears to return broken auxiliaryTopLeftArea /
            // auxiliaryTopRightArea on some builds, which produced a
            // notchWidth of ~2820pt and panel/wings that spanned the entire
            // screen. When the auxiliary areas are present but yield a
            // width outside this range, treat them as untrustworthy and
            // fall back to a centered estimate.
            let minSaneNotchWidth: CGFloat = 150
            let maxSaneNotchWidth: CGFloat = 400
            let estimatedWidth: CGFloat = 200

            let auxiliaryDerivedWidth: CGFloat = {
                guard leftArea != .zero, rightArea != .zero else { return -1 }
                return rightArea.minX - leftArea.maxX
            }()

            if auxiliaryDerivedWidth >= minSaneNotchWidth,
               auxiliaryDerivedWidth <= maxSaneNotchWidth {
                notchMinX = leftArea.maxX
                notchMaxX = rightArea.minX
            } else {
                notchMinX = frame.midX - estimatedWidth / 2
                notchMaxX = frame.midX + estimatedWidth / 2
            }

            NSLog("[NotchGeometry] safeTop=\(safeTop) frame=\(frame) leftArea=\(leftArea) rightArea=\(rightArea) auxDerivedWidth=\(auxiliaryDerivedWidth) finalNotchWidth=\(notchMaxX - notchMinX) screens=\(NSScreen.screens.count) localizedName=\(screen.localizedName)")

            return NotchGeometry(
                notchWidth: notchMaxX - notchMinX,
                notchHeight: safeTop,
                screenWidth: frame.width,
                screenHeight: frame.height,
                notchMinX: notchMinX,
                notchMaxX: notchMaxX,
                hasNotch: true,
                isFloatingMode: false
            )
        } else {
            // Floating mode (external display, no hardware notch): create
            // a virtual pill-shaped panel sized to the screen's actual
            // menu-bar height so the pill sits flush *under* the menu bar
            // edge instead of overhanging it. macOS mirrors the menu bar
            // onto every display by default, so this is normally ~24pt.
            // We only fall back to 32pt when the screen reports zero
            // chrome (rare — happens with "Displays have separate Spaces"
            // off and the screen isn't currently active).
            let floatingWidth: CGFloat = 200
            let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
            let floatingHeight: CGFloat = menuBarHeight > 0 ? menuBarHeight : 32
            let midX = frame.midX

            return NotchGeometry(
                notchWidth: floatingWidth,
                notchHeight: floatingHeight,
                screenWidth: frame.width,
                screenHeight: frame.height,
                notchMinX: midX - floatingWidth / 2,
                notchMaxX: midX + floatingWidth / 2,
                hasNotch: false,
                isFloatingMode: true
            )
        }
    }
}
