import Foundation

public enum AudioChannelMode: String, CaseIterable, Identifiable, Sendable, Codable {
    case stereo
    case reverse
    case left
    case right
    case dolby

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .stereo: return "Stereo"
        case .reverse: return "Reverse stereo"
        case .left: return "Left only"
        case .right: return "Right only"
        case .dolby: return "Dolby Surround"
        }
    }
}

public enum AudioReplayGainMode: String, CaseIterable, Identifiable, Sendable, Codable {
    case off
    case track
    case album

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .off: return "Off"
        case .track: return "Track"
        case .album: return "Album"
        }
    }

    public var mpvValue: String {
        switch self {
        case .off: return "no"
        case .track: return "track"
        case .album: return "album"
        }
    }
}

public enum AudioOutputModule: String, CaseIterable, Identifiable, Sendable, Codable {
    case auto
    case coreaudio
    case audiounit

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .coreaudio: return "Core Audio"
        case .audiounit: return "Audio Unit"
        }
    }

    public static var available: [AudioOutputModule] {
        #if os(macOS)
        [.auto, .coreaudio]
        #elseif os(iOS) || os(tvOS)
        [.auto, .audiounit]
        #else
        [.auto]
        #endif
    }

    /// Concrete `ao` value for mpv, or nil when Auto (platform default).
    public var mpvAO: String? {
        switch self {
        case .auto: return nil
        case .coreaudio: return "coreaudio"
        case .audiounit: return "audiounit"
        }
    }
}

public struct AudioEqualizerPreset: Identifiable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    /// Ten band gains in dB.
    public let bands: [Double]
    public let preamp: Double

    public init(id: String, displayName: String, bands: [Double], preamp: Double = 0) {
        self.id = id
        self.displayName = displayName
        self.bands = bands
        self.preamp = preamp
    }
}

public enum AudioEqualizerCatalog {
    /// VLC-style 10-band center frequencies (Hz).
    public static let bandFrequencies: [Double] = [
        60, 170, 310, 600, 1000, 3000, 6000, 12000, 14000, 16000
    ]

    public static let bandLabels: [String] = [
        "60", "170", "310", "600", "1k", "3k", "6k", "12k", "14k", "16k"
    ]

    public static let flatID = "flat"

    public static let presets: [AudioEqualizerPreset] = [
        AudioEqualizerPreset(id: "flat", displayName: "Flat", bands: Array(repeating: 0, count: 10)),
        AudioEqualizerPreset(id: "classical", displayName: "Classical", bands: [-1.1, -1.1, -1.1, -1.1, -1.1, -1.1, -7.2, -7.2, -7.2, -9.1]),
        AudioEqualizerPreset(id: "club", displayName: "Club", bands: [-1.1, -1.1, 8.0, 5.6, 5.6, 5.6, 3.2, -1.1, -1.1, -1.1]),
        AudioEqualizerPreset(id: "dance", displayName: "Dance", bands: [9.6, 7.2, 2.4, 0, 0, -5.6, -7.2, -7.2, -1.1, -1.1]),
        AudioEqualizerPreset(id: "fullbass", displayName: "Full bass", bands: [-8.0, 9.6, 9.6, 5.6, 1.6, -4.0, -8.0, -10.4, -11.2, -11.2]),
        AudioEqualizerPreset(id: "fullbasstreble", displayName: "Full bass & treble", bands: [7.2, 5.6, 0, -7.2, -4.8, 1.6, 8.0, 11.2, 12.0, 12.0]),
        AudioEqualizerPreset(id: "fulltreble", displayName: "Full treble", bands: [-9.6, -9.6, -9.6, -4.0, 2.4, 11.2, 16.0, 16.0, 16.0, 16.8]),
        AudioEqualizerPreset(id: "headphones", displayName: "Headphones", bands: [4.8, 11.2, 5.6, -3.2, -2.4, 1.6, 4.8, 9.6, 12.8, 14.4]),
        AudioEqualizerPreset(id: "largehall", displayName: "Large hall", bands: [10.4, 10.4, 5.6, 5.6, 0, -4.8, -4.8, -4.8, -1.1, -1.1]),
        AudioEqualizerPreset(id: "live", displayName: "Live", bands: [-4.8, 0, 4.0, 5.6, 5.6, 5.6, 4.0, 2.4, 2.4, 2.4]),
        AudioEqualizerPreset(id: "party", displayName: "Party", bands: [7.2, 7.2, 0, 0, 0, 0, 0, 0, 7.2, 7.2]),
        AudioEqualizerPreset(id: "pop", displayName: "Pop", bands: [-1.6, 4.8, 7.2, 8.0, 5.6, 0, -2.4, -2.4, -1.6, -1.6]),
        AudioEqualizerPreset(id: "reggae", displayName: "Reggae", bands: [0, 0, 0, -5.6, 0, 6.4, 6.4, 0, 0, 0]),
        AudioEqualizerPreset(id: "rock", displayName: "Rock", bands: [8.0, 4.8, -5.6, -8.0, -3.2, 4.0, 8.8, 11.2, 11.2, 11.2]),
        AudioEqualizerPreset(id: "ska", displayName: "Ska", bands: [-2.4, -4.8, -4.0, 0, 4.0, 5.6, 8.8, 9.6, 11.2, 9.6]),
        AudioEqualizerPreset(id: "soft", displayName: "Soft", bands: [4.8, 1.6, 0, -2.4, 0, 4.0, 8.0, 9.6, 11.2, 12.0]),
        AudioEqualizerPreset(id: "softrock", displayName: "Soft rock", bands: [4.0, 4.0, 2.4, 0, -4.0, -5.6, -3.2, 0, 2.4, 8.8]),
        AudioEqualizerPreset(id: "techno", displayName: "Techno", bands: [8.0, 5.6, 0, -5.6, -4.8, 0, 8.0, 9.6, 9.6, 8.8])
    ]

    public static func preset(id: String) -> AudioEqualizerPreset {
        presets.first(where: { $0.id == id }) ?? presets[0]
    }

    public static func normalizedBands(_ bands: [Double]) -> [Double] {
        var result = bands
        while result.count < 10 { result.append(0) }
        if result.count > 10 { result = Array(result.prefix(10)) }
        return result.map { min(20, max(-20, $0)) }
    }
}

public enum AudioFilterGraph {
    /// Builds an mpv `af` string from preferences. Returns nil when no filters are needed.
    public static func build(from preferences: KinemaPreferences) -> String? {
        var filters: [String] = []

        if preferences.audioForceMono {
            filters.append("lavfi=[pan=mono|c0=0.5*c0+0.5*c1]")
        } else {
            switch preferences.audioChannelMode {
            case .stereo:
                break
            case .reverse:
                filters.append("lavfi=[pan=stereo|c0=c1|c1=c0]")
            case .left:
                filters.append("lavfi=[pan=stereo|c0=c0|c1=c0]")
            case .right:
                filters.append("lavfi=[pan=stereo|c0=c1|c1=c1]")
            case .dolby:
                // Approximate Dolby Surround downmix into stereo.
                filters.append("lavfi=[pan=stereo|c0=c0+0.707*c2+0.707*c4|c1=c1+0.707*c2+0.707*c5]")
            }
        }

        if preferences.audioStereoWidenerEnabled {
            let m = String(format: "%.2f", max(0, min(4, preferences.audioStereoWidenerAmount)))
            filters.append("lavfi=[extrastereo=m=\(m)]")
        }

        if preferences.audioSpatializerEnabled {
            let amount = max(0, min(1, preferences.audioSpatializerAmount))
            let mlev = String(format: "%.2f", 0.05 + amount * 0.35)
            let slev = String(format: "%.2f", 1.0 + amount * 0.8)
            filters.append("lavfi=[stereotools=mlev=\(mlev):slev=\(slev)]")
        }

        if preferences.audioHeadphoneVirtualizer {
            filters.append("lavfi=[earwax]")
        }

        if preferences.audioEqualizerEnabled {
            let bands = AudioEqualizerCatalog.normalizedBands(preferences.audioEqualizerBands)
            let freqs = AudioEqualizerCatalog.bandFrequencies
            var eqParts: [String] = []
            for (index, gain) in bands.enumerated() where abs(gain) > 0.05 {
                let f = Int(freqs[index])
                let g = String(format: "%.2f", gain)
                eqParts.append("equalizer=f=\(f):t=o:w=1:g=\(g)")
            }
            let preamp = preferences.audioEqualizerPreamp
            if abs(preamp) > 0.05 {
                let linear = pow(10.0, preamp / 20.0)
                eqParts.append("volume=\(String(format: "%.4f", linear))")
            }
            if !eqParts.isEmpty {
                filters.append("lavfi=[\(eqParts.joined(separator: ","))]")
            }
        }

        if preferences.audioCompressorEnabled {
            let threshold = String(format: "%.1f", preferences.audioCompressorThreshold)
            let ratio = String(format: "%.2f", preferences.audioCompressorRatio)
            let attack = String(format: "%.0f", preferences.audioCompressorAttack)
            let release = String(format: "%.0f", preferences.audioCompressorRelease)
            let makeup = String(format: "%.1f", preferences.audioCompressorMakeup)
            filters.append(
                "lavfi=[acompressor=threshold=\(threshold)dB:ratio=\(ratio):attack=\(attack):release=\(release):makeup=\(makeup)dB]"
            )
        }

        if preferences.audioNormalizeEnabled {
            filters.append("lavfi=[dynaudnorm=f=150:g=15]")
        }

        let pitch = preferences.audioPitchScale
        if abs(pitch - 1.0) > 0.01 {
            let scale = String(format: "%.4f", max(0.5, min(1.5, pitch)))
            filters.append("rubberband=pitch-scale=\(scale)")
        }

        guard !filters.isEmpty else { return nil }
        return filters.joined(separator: ",")
    }
}
