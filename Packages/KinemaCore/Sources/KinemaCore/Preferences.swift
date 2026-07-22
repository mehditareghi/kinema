import Foundation

public struct KinemaPreferences: Sendable {
    public var volume: Double
    public var speed: Double
    public var resumePlayback: Bool
    public var autoLoadSubtitles: Bool
    public var subtitleFontSize: Int
    public var hardwareDecoding: Bool
    public var musicModeEnabled: Bool

    public init(
        volume: Double = 100,
        speed: Double = 1,
        resumePlayback: Bool = true,
        autoLoadSubtitles: Bool = true,
        subtitleFontSize: Int = 55,
        hardwareDecoding: Bool = true,
        musicModeEnabled: Bool = false
    ) {
        self.volume = volume
        self.speed = speed
        self.resumePlayback = resumePlayback
        self.autoLoadSubtitles = autoLoadSubtitles
        self.subtitleFontSize = subtitleFontSize
        self.hardwareDecoding = hardwareDecoding
        self.musicModeEnabled = musicModeEnabled
    }
}

@MainActor
@Observable
public final class PreferencesStore {
    public static let shared = PreferencesStore()

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let volume = "kinema.volume"
        static let speed = "kinema.speed"
        static let resumePlayback = "kinema.resumePlayback"
        static let autoLoadSubtitles = "kinema.autoLoadSubtitles"
        static let subtitleFontSize = "kinema.subtitleFontSize"
        static let hardwareDecoding = "kinema.hardwareDecoding"
        static let musicModeEnabled = "kinema.musicModeEnabled"
    }

    public var preferences: KinemaPreferences {
        didSet { persist() }
    }

    private init() {
        preferences = KinemaPreferences(
            volume: defaults.object(forKey: Keys.volume) as? Double ?? 100,
            speed: defaults.object(forKey: Keys.speed) as? Double ?? 1,
            resumePlayback: defaults.object(forKey: Keys.resumePlayback) as? Bool ?? true,
            autoLoadSubtitles: defaults.object(forKey: Keys.autoLoadSubtitles) as? Bool ?? true,
            subtitleFontSize: defaults.object(forKey: Keys.subtitleFontSize) as? Int ?? 55,
            hardwareDecoding: defaults.object(forKey: Keys.hardwareDecoding) as? Bool ?? true,
            musicModeEnabled: defaults.object(forKey: Keys.musicModeEnabled) as? Bool ?? false
        )
    }

    private func persist() {
        defaults.set(preferences.volume, forKey: Keys.volume)
        defaults.set(preferences.speed, forKey: Keys.speed)
        defaults.set(preferences.resumePlayback, forKey: Keys.resumePlayback)
        defaults.set(preferences.autoLoadSubtitles, forKey: Keys.autoLoadSubtitles)
        defaults.set(preferences.subtitleFontSize, forKey: Keys.subtitleFontSize)
        defaults.set(preferences.hardwareDecoding, forKey: Keys.hardwareDecoding)
        defaults.set(preferences.musicModeEnabled, forKey: Keys.musicModeEnabled)
    }

    public func mpvOptions() -> [String: String] {
        var options: [String: String] = [
            "volume": "\(Int(preferences.volume))",
            "speed": "\(preferences.speed)",
            "sub-font-size": "\(preferences.subtitleFontSize)",
            "sub-border-size": "2",
            "sub-shadow-offset": "1",
            "keep-open": "yes",
            "hr-seek": "yes"
        ]
        if preferences.hardwareDecoding {
            options["hwdec"] = "auto-safe"
        } else {
            options["hwdec"] = "no"
        }
        return options
    }
}
