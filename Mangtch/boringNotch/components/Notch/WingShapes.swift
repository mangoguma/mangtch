import SwiftUI

// MARK: - Wing Shape (boring-notch style)

/// Half of the boring-notch pill, mirrored per wing. The signature
/// detail is the **concave inset at the top-outer corner**: starting
/// from the screen-edge corner, the boundary curves *inward* toward the
/// wing interior before resuming the side edge — giving the panel its
/// "scooped" top look (`topOuterRadius`). The bottom-outer corner is a
/// regular convex round (`bottomOuterRadius`); inner edges (toward the
/// notch body) are square so adjacent wings + notch body merge flush.
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
            p.move(to: .zero)
            p.addQuadCurve(to: CGPoint(x: tr, y: tr), control: CGPoint(x: tr, y: 0))
            p.addLine(to: CGPoint(x: tr, y: h - br))
            p.addQuadCurve(to: CGPoint(x: tr + br, y: h), control: CGPoint(x: tr, y: h))
            p.addLine(to: CGPoint(x: w, y: h))
            p.addLine(to: CGPoint(x: w, y: 0))
            p.closeSubpath()
        case .right:
            // Mirror of left.
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

// MARK: - Expanded Panel Shape

/// Bottom-rounded panel chrome whose top edges sit `outerInset` pixels
/// inside the frame on each side. Pairs with `WingShape`'s boring-notch-style
/// top-outer concave so the panel chrome insets to align flush with the wings'
/// visible side edges.
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

    static func detect(for screen: NSScreen?) -> NotchGeometry {
        guard let screen = screen else {
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
            let leftArea = screen.auxiliaryTopLeftArea ?? .zero
            let rightArea = screen.auxiliaryTopRightArea ?? .zero

            let minSaneNotchWidth: CGFloat = 150
            let maxSaneNotchWidth: CGFloat = 400
            let estimatedWidth: CGFloat = 200

            let auxiliaryDerivedWidth: CGFloat = {
                guard leftArea != .zero, rightArea != .zero else { return -1 }
                return rightArea.minX - leftArea.maxX
            }()

            let notchMinX: CGFloat
            let notchMaxX: CGFloat
            if auxiliaryDerivedWidth >= minSaneNotchWidth,
               auxiliaryDerivedWidth <= maxSaneNotchWidth {
                notchMinX = leftArea.maxX
                notchMaxX = rightArea.minX
            } else {
                notchMinX = frame.midX - estimatedWidth / 2
                notchMaxX = frame.midX + estimatedWidth / 2
            }

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
