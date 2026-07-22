import Foundation

public struct SubtitleFontOption: Identifiable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    /// Empty means mpv's default font.
    public let mpvFontName: String

    public init(id: String, displayName: String, mpvFontName: String) {
        self.id = id
        self.displayName = displayName
        self.mpvFontName = mpvFontName
    }
}

public struct SubtitleEncodingOption: Identifiable, Hashable, Sendable {
    public let id: String
    public let displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

public enum SubtitlePreferenceCatalog {
    public static let defaultFontID = SubtitleFontRegistry.systemDefaultID
    public static let defaultColorHex = "#FFFFFFFF"
    public static let defaultEncodingID = "utf-8"

    public static let encodings: [SubtitleEncodingOption] = [
        SubtitleEncodingOption(id: "utf-8", displayName: "UTF-8"),
        SubtitleEncodingOption(id: "utf-16", displayName: "UTF-16"),
        SubtitleEncodingOption(id: "windows-1252", displayName: "Windows-1252 (Western)"),
        SubtitleEncodingOption(id: "windows-1256", displayName: "Windows-1256 (Arabic/Persian)"),
        SubtitleEncodingOption(id: "iso-8859-1", displayName: "ISO-8859-1 (Latin-1)"),
        SubtitleEncodingOption(id: "iso-8859-6", displayName: "ISO-8859-6 (Arabic)"),
        SubtitleEncodingOption(id: "gb18030", displayName: "GB18030 (Chinese)"),
        SubtitleEncodingOption(id: "big5", displayName: "Big5 (Traditional Chinese)"),
        SubtitleEncodingOption(id: "shift_jis", displayName: "Shift_JIS (Japanese)"),
        SubtitleEncodingOption(id: "euc-kr", displayName: "EUC-KR (Korean)"),
        SubtitleEncodingOption(id: "koi8-r", displayName: "KOI8-R (Cyrillic)")
    ]

    public static func encoding(id: String) -> SubtitleEncodingOption {
        encodings.first(where: { $0.id == id }) ?? encodings[0]
    }
}

public struct KinemaPreferences: Sendable {
    public var volume: Double
    public var speed: Double
    public var resumePlayback: Bool
    public var autoLoadSubtitles: Bool
    public var subtitleFontSize: Int
    /// Empty = system default; otherwise a font family name (VLC-style).
    public var subtitleFontID: String
    public var subtitleColorHex: String
    public var subtitleEncodingID: String
    public var hardwareDecoding: Bool
    public var musicModeEnabled: Bool

    public init(
        volume: Double = 100,
        speed: Double = 1,
        resumePlayback: Bool = true,
        autoLoadSubtitles: Bool = true,
        subtitleFontSize: Int = 55,
        subtitleFontID: String = SubtitlePreferenceCatalog.defaultFontID,
        subtitleColorHex: String = SubtitlePreferenceCatalog.defaultColorHex,
        subtitleEncodingID: String = SubtitlePreferenceCatalog.defaultEncodingID,
        hardwareDecoding: Bool = true,
        musicModeEnabled: Bool = false
    ) {
        self.volume = volume
        self.speed = speed
        self.resumePlayback = resumePlayback
        self.autoLoadSubtitles = autoLoadSubtitles
        self.subtitleFontSize = subtitleFontSize
        self.subtitleFontID = subtitleFontID
        self.subtitleColorHex = subtitleColorHex
        self.subtitleEncodingID = subtitleEncodingID
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
        static let subtitleFontID = "kinema.subtitleFontID"
        static let subtitleColorHex = "kinema.subtitleColorHex"
        static let subtitleEncodingID = "kinema.subtitleEncodingID"
        static let hardwareDecoding = "kinema.hardwareDecoding"
        static let musicModeEnabled = "kinema.musicModeEnabled"
    }

    public var preferences: KinemaPreferences {
        didSet { persist() }
    }

    private init() {
        _ = SubtitleFontRegistry.prepare()
        let storedFont = defaults.string(forKey: Keys.subtitleFontID) ?? SubtitlePreferenceCatalog.defaultFontID
        preferences = KinemaPreferences(
            volume: defaults.object(forKey: Keys.volume) as? Double ?? 100,
            speed: defaults.object(forKey: Keys.speed) as? Double ?? 1,
            resumePlayback: defaults.object(forKey: Keys.resumePlayback) as? Bool ?? true,
            autoLoadSubtitles: defaults.object(forKey: Keys.autoLoadSubtitles) as? Bool ?? true,
            subtitleFontSize: defaults.object(forKey: Keys.subtitleFontSize) as? Int ?? 55,
            subtitleFontID: SubtitleFontRegistry.migrateLegacyFontID(storedFont),
            subtitleColorHex: defaults.string(forKey: Keys.subtitleColorHex) ?? SubtitlePreferenceCatalog.defaultColorHex,
            subtitleEncodingID: defaults.string(forKey: Keys.subtitleEncodingID) ?? SubtitlePreferenceCatalog.defaultEncodingID,
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
        defaults.set(preferences.subtitleFontID, forKey: Keys.subtitleFontID)
        defaults.set(preferences.subtitleColorHex, forKey: Keys.subtitleColorHex)
        defaults.set(preferences.subtitleEncodingID, forKey: Keys.subtitleEncodingID)
        defaults.set(preferences.hardwareDecoding, forKey: Keys.hardwareDecoding)
        defaults.set(preferences.musicModeEnabled, forKey: Keys.musicModeEnabled)
    }

    public func mpvOptions() -> [String: String] {
        let fontsDir = SubtitleFontRegistry.prepare()
        let selectedFont = SubtitleFontRegistry.resolveStoredFontSelection(preferences.subtitleFontID)

        var options: [String: String] = [
            "volume": "\(Int(preferences.volume))",
            "speed": "\(preferences.speed)",
            "sub-font-size": "\(preferences.subtitleFontSize)",
            "sub-color": normalizedSubtitleColorHex(preferences.subtitleColorHex),
            "sub-border-size": "2",
            "sub-shadow-offset": "1",
            "sub-codepage": SubtitlePreferenceCatalog.encoding(id: preferences.subtitleEncodingID).id,
            "keep-open": "yes",
            "hr-seek": "yes"
        ]

        if let fontsDir {
            options["sub-fonts-dir"] = fontsDir.path
        }

        if !selectedFont.mpvFontName.isEmpty {
            options["sub-font"] = selectedFont.mpvFontName
        }

        if preferences.hardwareDecoding {
            options["hwdec"] = "auto-safe"
        } else {
            options["hwdec"] = "no"
        }
        return options
    }
}

public func normalizedSubtitleColorHex(_ hex: String) -> String {
    var value = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    if value.hasPrefix("#") {
        value.removeFirst()
    }
    switch value.count {
    case 6:
        return "#FF\(value)"
    case 8:
        return "#\(value)"
    default:
        return SubtitlePreferenceCatalog.defaultColorHex
    }
}
