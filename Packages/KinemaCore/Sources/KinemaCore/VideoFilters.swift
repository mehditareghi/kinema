import Foundation

/// Playback picture equalizer + light enhance filters (mpv brightness/eq + vf).
public struct VideoFilterSettings: Codable, Sendable, Equatable {
    public static let equalizerRange: ClosedRange<Double> = -100...100
    public static let sharpenRange: ClosedRange<Double> = 0...5

    /// mpv `brightness` (−100…100).
    public var brightness: Double
    /// mpv `contrast` (−100…100).
    public var contrast: Double
    /// mpv `saturation` (−100…100).
    public var saturation: Double
    /// mpv `gamma` (−100…100).
    public var gamma: Double
    /// mpv `deband`.
    public var debandEnabled: Bool
    /// mpv `vf=sharpen=` amount; 0 disables.
    public var sharpen: Double

    public init(
        brightness: Double = 0,
        contrast: Double = 0,
        saturation: Double = 0,
        gamma: Double = 0,
        debandEnabled: Bool = false,
        sharpen: Double = 0
    ) {
        self.brightness = Self.clampEqualizer(brightness)
        self.contrast = Self.clampEqualizer(contrast)
        self.saturation = Self.clampEqualizer(saturation)
        self.gamma = Self.clampEqualizer(gamma)
        self.debandEnabled = debandEnabled
        self.sharpen = Self.clampSharpen(sharpen)
    }

    public var isAtDefaults: Bool {
        abs(brightness) < 0.01
            && abs(contrast) < 0.01
            && abs(saturation) < 0.01
            && abs(gamma) < 0.01
            && !debandEnabled
            && sharpen < 0.01
    }

    public mutating func reset() {
        self = VideoFilterSettings()
    }

    /// Builds an mpv `vf` graph (currently sharpen only; eq uses dedicated properties).
    public var videoFilterGraph: String? {
        let amount = Self.clampSharpen(sharpen)
        guard amount >= 0.05 else { return nil }
        return String(format: "sharpen=%.2f", amount)
    }

    public static func clampEqualizer(_ value: Double) -> Double {
        min(equalizerRange.upperBound, max(equalizerRange.lowerBound, value))
    }

    public static func clampSharpen(_ value: Double) -> Double {
        min(sharpenRange.upperBound, max(sharpenRange.lowerBound, value))
    }
}
