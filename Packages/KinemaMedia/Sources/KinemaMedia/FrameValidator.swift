import CoreGraphics
import Foundation

public enum MediaFrameValidator {
    /// Rejects blank, solid-gray, or obviously corrupt decoder frames.
    public static func isAcceptable(_ image: CGImage) -> Bool {
        guard image.width > 8, image.height > 8 else { return false }

        let sampleWidth = 48
        let sampleHeight = 27
        let bytesPerPixel = 4
        let bytesPerRow = sampleWidth * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: sampleHeight * bytesPerRow)

        guard let context = CGContext(
            data: &pixels,
            width: sampleWidth,
            height: sampleHeight,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return false
        }

        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))

        var luminance = [Double]()
        var saturation = [Double]()
        luminance.reserveCapacity(sampleWidth * sampleHeight)
        saturation.reserveCapacity(sampleWidth * sampleHeight)

        for row in 0 ..< sampleHeight {
            let base = row * bytesPerRow
            for col in 0 ..< sampleWidth {
                let index = base + col * bytesPerPixel
                let r = Double(pixels[index])
                let g = Double(pixels[index + 1])
                let b = Double(pixels[index + 2])
                luminance.append((0.2126 * r) + (0.7152 * g) + (0.0722 * b))
                let maxChannel = max(r, g, b)
                let minChannel = min(r, g, b)
                saturation.append(maxChannel > 0 ? (maxChannel - minChannel) / maxChannel : 0)
            }
        }

        guard !luminance.isEmpty else { return false }

        let mean = luminance.reduce(0, +) / Double(luminance.count)
        let variance = luminance.reduce(0) { $0 + pow($1 - mean, 2) } / Double(luminance.count)
        let averageSaturation = saturation.reduce(0, +) / Double(saturation.count)

        if variance < 120 {
            return false
        }

        let nearMean = luminance.filter { abs($0 - mean) < 18 }.count
        if Double(nearMean) / Double(luminance.count) > 0.90 {
            return false
        }

        if mean < 8 || mean > 248 {
            return false
        }

        // Decoder junk often looks like a flat gray wash with almost no color.
        if averageSaturation < 0.045, mean > 55, mean < 205 {
            return false
        }

        return true
    }
}

enum FrameValidator {
    static func isAcceptable(_ image: CGImage) -> Bool {
        MediaFrameValidator.isAcceptable(image)
    }
}