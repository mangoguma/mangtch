import AppKit
import CoreImage

/// Extracts dominant and secondary colors from an NSImage using CIFilter-based analysis.
struct ColorExtractor {

    struct Palette {
        let dominant: NSColor
        let secondary: NSColor

        /// Whether the palette is "dark" (dominant luminance < 0.5)
        var isDark: Bool {
            dominant.luminance < 0.5
        }
    }

    /// Extract a 2-color palette from the given image.
    /// Uses area-average + histogram approach for reliable, fast extraction.
    static func extract(from image: NSImage) -> Palette {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return defaultPalette
        }

        let ciImage = CIImage(cgImage: cgImage)

        // Resize to small thumbnail for speed
        let scale = 50.0 / max(Double(cgImage.width), Double(cgImage.height))
        let resized = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        // Get pixel data
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        let extent = resized.extent

        guard extent.width > 0, extent.height > 0 else { return defaultPalette }

        let width = Int(extent.width)
        let height = Int(extent.height)
        var bitmap = [UInt8](repeating: 0, count: width * height * 4)

        context.render(
            resized,
            toBitmap: &bitmap,
            rowBytes: width * 4,
            bounds: extent,
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        // Collect colors into buckets
        var colorBuckets: [ColorBucket] = []
        let bucketSize = 32 // Group similar colors

        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let r = Int(bitmap[i])
                let g = Int(bitmap[i + 1])
                let b = Int(bitmap[i + 2])

                // Quantize to buckets
                let br = (r / bucketSize) * bucketSize + bucketSize / 2
                let bg = (g / bucketSize) * bucketSize + bucketSize / 2
                let bb = (b / bucketSize) * bucketSize + bucketSize / 2

                if let idx = colorBuckets.firstIndex(where: { $0.r == br && $0.g == bg && $0.b == bb }) {
                    colorBuckets[idx].count += 1
                } else {
                    colorBuckets.append(ColorBucket(r: br, g: bg, b: bb, count: 1))
                }
            }
        }

        // Sort by frequency
        colorBuckets.sort { $0.count > $1.count }

        // Filter out near-black and near-white
        let filtered = colorBuckets.filter { bucket in
            let lum = 0.299 * Double(bucket.r) + 0.587 * Double(bucket.g) + 0.114 * Double(bucket.b)
            return lum > 30 && lum < 240
        }

        let dominant: NSColor
        let secondary: NSColor

        if let first = filtered.first {
            dominant = NSColor(
                red: CGFloat(first.r) / 255,
                green: CGFloat(first.g) / 255,
                blue: CGFloat(first.b) / 255,
                alpha: 1.0
            )

            // Find secondary: most popular color that's visually different
            let secondBucket = filtered.dropFirst().first(where: { bucket in
                let dr = abs(bucket.r - first.r)
                let dg = abs(bucket.g - first.g)
                let db = abs(bucket.b - first.b)
                return dr + dg + db > 60 // Minimum color distance
            }) ?? filtered.dropFirst().first

            if let sb = secondBucket {
                secondary = NSColor(
                    red: CGFloat(sb.r) / 255,
                    green: CGFloat(sb.g) / 255,
                    blue: CGFloat(sb.b) / 255,
                    alpha: 1.0
                )
            } else {
                secondary = dominant.adjusted(brightness: 0.3)
            }
        } else {
            return defaultPalette
        }

        return Palette(dominant: dominant, secondary: secondary)
    }

    // MARK: - Private

    private struct ColorBucket {
        let r: Int
        let g: Int
        let b: Int
        var count: Int
    }

    private static var defaultPalette: Palette {
        Palette(
            dominant: NSColor(red: 0.15, green: 0.15, blue: 0.2, alpha: 1),
            secondary: NSColor(red: 0.3, green: 0.3, blue: 0.4, alpha: 1)
        )
    }
}

// MARK: - NSColor Helpers

extension NSColor {
    var luminance: CGFloat {
        guard let rgb = usingColorSpace(.deviceRGB) else { return 0.5 }
        return 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
    }

    func adjusted(brightness delta: CGFloat) -> NSColor {
        guard let rgb = usingColorSpace(.deviceRGB) else { return self }
        return NSColor(
            red: min(1, max(0, rgb.redComponent + delta)),
            green: min(1, max(0, rgb.greenComponent + delta)),
            blue: min(1, max(0, rgb.blueComponent + delta)),
            alpha: rgb.alphaComponent
        )
    }
}
