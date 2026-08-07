import CoreGraphics
import Foundation

public enum MediaFrameValidator {
    public struct Metrics: Sendable {
        public let meanLuminance: Double
        public let variance: Double
        public let averageSaturation: Double
        public let nearMeanRatio: Double
        /// Fraction of sampled pixels that are nearly achromatic (R≈G≈B).
        public let grayPixelRatio: Double
        /// Fraction of spatial tiles that look like flat mid-gray decoder wash / macroblocks.
        public let deadTileRatio: Double

        /// Higher is better. Tuned so typical scene frames beat fades, flats, and decoder wash.
        public var qualityScore: Double {
            let contrast = min(variance, 8_000) / 8_000
            let color = min(averageSaturation, 0.35) / 0.35
            let midtone = 1 - abs(meanLuminance - 128) / 128
            let uniformityPenalty = max(0, nearMeanRatio - 0.50) * 1.6
            let grayPenalty = max(0, grayPixelRatio - 0.55) * 1.2
            let deadPenalty = deadTileRatio * 1.8
            return (contrast * 0.50) + (color * 0.35) + (midtone * 0.15)
                - uniformityPenalty - grayPenalty - deadPenalty
        }
    }

    /// Minimum score we'll accept as a library poster. Below this, try another seek.
    public static let minimumAcceptableScore: Double = 0.22

    /// Rejects blank, solid-gray, corrupt (macroblock), or obviously bad decoder frames.
    public static func isAcceptable(_ image: CGImage) -> Bool {
        guard let metrics = metrics(for: image) else { return false }
        return metrics.qualityScore >= minimumAcceptableScore
    }

    /// Quality score for ranking candidate frames. `nil` when the frame should be rejected.
    public static func qualityScore(for image: CGImage) -> Double? {
        guard let metrics = metrics(for: image) else { return nil }
        guard metrics.qualityScore >= minimumAcceptableScore else { return nil }
        return metrics.qualityScore
    }

    public static func metrics(for image: CGImage) -> Metrics? {
        guard image.width > 8, image.height > 8 else { return nil }

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
            return nil
        }

        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))

        var luminance = [Double]()
        var saturation = [Double]()
        luminance.reserveCapacity(sampleWidth * sampleHeight)
        saturation.reserveCapacity(sampleWidth * sampleHeight)
        var grayPixels = 0

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
                let sat = maxChannel > 0 ? (maxChannel - minChannel) / maxChannel : 0
                saturation.append(sat)
                if sat < 0.06, maxChannel - minChannel < 14 {
                    grayPixels += 1
                }
            }
        }

        guard !luminance.isEmpty else { return nil }

        let mean = luminance.reduce(0, +) / Double(luminance.count)
        let variance = luminance.reduce(0) { $0 + pow($1 - mean, 2) } / Double(luminance.count)
        let averageSaturation = saturation.reduce(0, +) / Double(saturation.count)
        let nearMean = luminance.filter { abs($0 - mean) < 18 }.count
        let nearMeanRatio = Double(nearMean) / Double(luminance.count)
        let grayPixelRatio = Double(grayPixels) / Double(luminance.count)
        let deadTileRatio = deadMacroblockRatio(
            luminance: luminance,
            saturation: saturation,
            width: sampleWidth,
            height: sampleHeight
        )

        // Flat / near-uniform frames (solid color, decoder wash).
        if variance < 220 {
            return nil
        }

        if nearMeanRatio > 0.82 {
            return nil
        }

        // Near-black / near-white.
        if mean < 16 || mean > 242 {
            return nil
        }

        // Mostly achromatic image — classic gray thumbnail.
        if grayPixelRatio > 0.78 {
            return nil
        }

        // Incomplete decode: large mid-gray macroblock patches mixed with real content
        // (exactly the "face in a sea of gray blocks" artifact).
        if deadTileRatio > 0.22 {
            return nil
        }

        // Decoder junk: flat gray wash with almost no color.
        if averageSaturation < 0.07, mean > 40, mean < 215 {
            return nil
        }

        // Soft fade / letterbox mush: low contrast and low color together.
        if variance < 360, averageSaturation < 0.10 {
            return nil
        }

        // Gray-dominant midtones with little chroma even if variance looks OK (noise).
        if grayPixelRatio > 0.62, averageSaturation < 0.11, mean > 50, mean < 200 {
            return nil
        }

        return Metrics(
            meanLuminance: mean,
            variance: variance,
            averageSaturation: averageSaturation,
            nearMeanRatio: nearMeanRatio,
            grayPixelRatio: grayPixelRatio,
            deadTileRatio: deadTileRatio
        )
    }

    /// Counts tiles that look like solid mid-gray macroblocks (not letterbox black).
    private static func deadMacroblockRatio(
        luminance: [Double],
        saturation: [Double],
        width: Int,
        height: Int
    ) -> Double {
        let tilesX = 8
        let tilesY = 5
        let tileW = width / tilesX
        let tileH = height / tilesY
        guard tileW > 0, tileH > 0 else { return 0 }

        var dead = 0
        var total = 0

        for ty in 0 ..< tilesY {
            for tx in 0 ..< tilesX {
                total += 1
                var sum = 0.0
                var sumSat = 0.0
                var count = 0
                let rowStart = ty * tileH
                let colStart = tx * tileW
                let rowEnd = (ty == tilesY - 1) ? height : rowStart + tileH
                let colEnd = (tx == tilesX - 1) ? width : colStart + tileW

                for row in rowStart ..< rowEnd {
                    for col in colStart ..< colEnd {
                        let index = row * width + col
                        sum += luminance[index]
                        sumSat += saturation[index]
                        count += 1
                    }
                }
                guard count > 0 else { continue }

                let tileMean = sum / Double(count)
                let tileSat = sumSat / Double(count)
                var tileVar = 0.0
                for row in rowStart ..< rowEnd {
                    for col in colStart ..< colEnd {
                        let index = row * width + col
                        let d = luminance[index] - tileMean
                        tileVar += d * d
                    }
                }
                tileVar /= Double(count)

                // Mid-gray, flat, nearly colorless tile → decoder garbage (not letterbox).
                if tileVar < 90, tileSat < 0.07, tileMean > 38, tileMean < 205 {
                    dead += 1
                }
            }
        }

        return total > 0 ? Double(dead) / Double(total) : 0
    }
}

enum FrameValidator {
    static func isAcceptable(_ image: CGImage) -> Bool {
        MediaFrameValidator.isAcceptable(image)
    }

    static func qualityScore(for image: CGImage) -> Double? {
        MediaFrameValidator.qualityScore(for: image)
    }
}
