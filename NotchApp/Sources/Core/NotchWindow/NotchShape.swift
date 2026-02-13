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
        case .idle:
            // Just the notch area - minimal rectangle matching physical notch
            path.addRoundedRect(
                in: CGRect(
                    x: midX - halfNotch,
                    y: 0,
                    width: notchWidth,
                    height: notchHeight
                ),
                cornerSize: CGSize(width: cornerRadius, height: cornerRadius)
            )

        case .hovering:
            // Wings extend from notch sides
            let wingWidth: CGFloat = (rect.width - notchWidth) / 2

            // Left wing
            path.move(to: CGPoint(x: rect.minX + cornerRadius, y: 0))
            path.addLine(to: CGPoint(x: midX - halfNotch, y: 0))

            // Notch cutout (skip over physical notch)
            path.move(to: CGPoint(x: midX + halfNotch, y: 0))

            // Right wing
            path.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: 0))
            path.addArc(
                center: CGPoint(x: rect.maxX - cornerRadius, y: cornerRadius),
                radius: cornerRadius,
                startAngle: .degrees(-90),
                endAngle: .degrees(0),
                clockwise: false
            )
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
            path.addLine(to: CGPoint(x: rect.minX, y: cornerRadius))
            path.addArc(
                center: CGPoint(x: rect.minX + cornerRadius, y: cornerRadius),
                radius: cornerRadius,
                startAngle: .degrees(180),
                endAngle: .degrees(270),
                clockwise: false
            )

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
        // IMPORTANT: Use screens[0] (built-in display) instead of .main
        // because .main returns the screen with focus, which might be external
        guard let screen = NSScreen.screens.first else {
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

            if leftArea != .zero && rightArea != .zero {
                notchMinX = leftArea.maxX
                notchMaxX = rightArea.minX
            } else {
                // Fallback: estimate from screen center
                let estimatedWidth: CGFloat = 180
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
            // Floating mode: create a virtual pill-shaped panel
            let floatingWidth: CGFloat = 200
            let floatingHeight: CGFloat = 8 // Small grab area at top
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
