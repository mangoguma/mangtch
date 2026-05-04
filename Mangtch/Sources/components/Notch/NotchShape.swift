import SwiftUI

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
