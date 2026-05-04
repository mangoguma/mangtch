import SwiftUI
import AppKit

extension Color {
    /// Boost a color so it meets a minimum WCAG contrast ratio against
    /// `background`. We extract sRGB components, compute relative
    /// luminance, then iteratively brighten the colour by blending toward
    /// white until the target ratio is met. Saturation is also clamped to
    /// avoid washed-out gray (low) or fluorescent (high) results.
    ///
    /// `targetRatio` defaults to 4.5 (WCAG AA for normal text). Use 3.0
    /// for large text / UI components.
    func contrastBoosted(against background: Color = .black,
                         targetRatio: CGFloat = 4.5,
                         minSaturation: CGFloat = 0.35,
                         maxSaturation: CGFloat = 0.85) -> Color {
        guard var rgba = Self.sRGBComponents(of: self) else { return self }
        let bgL = Self.relativeLuminance(of: background) ?? 0

        // Clamp saturation to the readable band first. Convert to HSB,
        // adjust, convert back.
        if let hsba = Self.hsbComponents(r: rgba.r, g: rgba.g, b: rgba.b) {
            var s = hsba.s
            if s < minSaturation { s = minSaturation }
            if s > maxSaturation { s = maxSaturation }
            let bumped = NSColor(hue: hsba.h, saturation: s,
                                 brightness: hsba.b, alpha: 1)
                .usingColorSpace(.sRGB) ?? NSColor.white
            rgba.r = bumped.redComponent
            rgba.g = bumped.greenComponent
            rgba.b = bumped.blueComponent
        }

        // Bisect a blend factor toward white until the contrast clears.
        // 32 iterations is far more than needed but keeps the function
        // simple and bounded.
        let target = max(targetRatio, 1)
        var t: CGFloat = 0
        var step: CGFloat = 1
        for _ in 0..<32 {
            let blendT = min(1, t + step)
            let candidate = (
                r: rgba.r + (1 - rgba.r) * blendT,
                g: rgba.g + (1 - rgba.g) * blendT,
                b: rgba.b + (1 - rgba.b) * blendT
            )
            let cL = Self.luminance(r: candidate.r, g: candidate.g, b: candidate.b)
            let ratio = (max(cL, bgL) + 0.05) / (min(cL, bgL) + 0.05)
            if ratio >= target {
                t = blendT
                break
            }
            step *= 0.5
            t = blendT
        }

        let final = (
            r: rgba.r + (1 - rgba.r) * t,
            g: rgba.g + (1 - rgba.g) * t,
            b: rgba.b + (1 - rgba.b) * t
        )
        return Color(red: final.r, green: final.g, blue: final.b, opacity: rgba.a)
    }

    // MARK: - Internals

    private static func sRGBComponents(of color: Color) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)? {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        guard let converted = ns.usingColorSpace(.sRGB) else { return nil }
        return (converted.redComponent, converted.greenComponent,
                converted.blueComponent, converted.alphaComponent)
    }

    private static func hsbComponents(r: CGFloat, g: CGFloat, b: CGFloat)
        -> (h: CGFloat, s: CGFloat, b: CGFloat)? {
        let ns = NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, br: CGFloat = 0, a: CGFloat = 0
        ns.getHue(&h, saturation: &s, brightness: &br, alpha: &a)
        return (h, s, br)
    }

    private static func relativeLuminance(of color: Color) -> CGFloat? {
        guard let c = sRGBComponents(of: color) else { return nil }
        return luminance(r: c.r, g: c.g, b: c.b)
    }

    /// WCAG 2.1 relative luminance for sRGB.
    private static func luminance(r: CGFloat, g: CGFloat, b: CGFloat) -> CGFloat {
        func channel(_ v: CGFloat) -> CGFloat {
            v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }
}
