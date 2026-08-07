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

public struct SubtitleLanguageOption: Identifiable, Hashable, Sendable {
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
    public static let defaultBorderColorHex = "#FF000000"
    public static let defaultShadowColorHex = "#80000000"
    public static let defaultBackColorHex = "#00000000"

    public static let popularLanguages: [SubtitleLanguageOption] = [
        SubtitleLanguageOption(id: "en", displayName: "English"),
        SubtitleLanguageOption(id: "fa", displayName: "Persian (Farsi)"),
        SubtitleLanguageOption(id: "ar", displayName: "Arabic"),
        SubtitleLanguageOption(id: "es", displayName: "Spanish"),
        SubtitleLanguageOption(id: "fr", displayName: "French"),
        SubtitleLanguageOption(id: "de", displayName: "German"),
        SubtitleLanguageOption(id: "it", displayName: "Italian"),
        SubtitleLanguageOption(id: "pt", displayName: "Portuguese"),
        SubtitleLanguageOption(id: "tr", displayName: "Turkish"),
        SubtitleLanguageOption(id: "ru", displayName: "Russian"),
        SubtitleLanguageOption(id: "zh", displayName: "Chinese"),
        SubtitleLanguageOption(id: "ja", displayName: "Japanese"),
        SubtitleLanguageOption(id: "ko", displayName: "Korean"),
        SubtitleLanguageOption(id: "hi", displayName: "Hindi"),
        SubtitleLanguageOption(id: "nl", displayName: "Dutch"),
        SubtitleLanguageOption(id: "pl", displayName: "Polish"),
        SubtitleLanguageOption(id: "sv", displayName: "Swedish")
    ]

    public static func language(id: String) -> SubtitleLanguageOption {
        let normalized = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let match = popularLanguages.first(where: { $0.id == normalized }) {
            return match
        }
        let code = normalized.isEmpty ? "en" : normalized
        return SubtitleLanguageOption(id: code, displayName: code.uppercased())
    }

    public static let encodings: [SubtitleEncodingOption] = [
        SubtitleEncodingOption(id: "utf-8", displayName: "UTF-8"),
        SubtitleEncodingOption(id: "utf-16", displayName: "UTF-16"),
        SubtitleEncodingOption(id: "windows-1250", displayName: "Windows-1250 (Central European)"),
        SubtitleEncodingOption(id: "windows-1251", displayName: "Windows-1251 (Cyrillic)"),
        SubtitleEncodingOption(id: "windows-1252", displayName: "Windows-1252 (Western)"),
        SubtitleEncodingOption(id: "windows-1256", displayName: "Windows-1256 (Arabic/Persian)"),
        SubtitleEncodingOption(id: "iso-8859-1", displayName: "ISO-8859-1 (Latin-1)"),
        SubtitleEncodingOption(id: "iso-8859-2", displayName: "ISO-8859-2 (Central European)"),
        SubtitleEncodingOption(id: "iso-8859-5", displayName: "ISO-8859-5 (Cyrillic)"),
        SubtitleEncodingOption(id: "iso-8859-6", displayName: "ISO-8859-6 (Arabic)"),
        SubtitleEncodingOption(id: "iso-8859-7", displayName: "ISO-8859-7 (Greek)"),
        SubtitleEncodingOption(id: "iso-8859-8", displayName: "ISO-8859-8 (Hebrew)"),
        SubtitleEncodingOption(id: "iso-8859-9", displayName: "ISO-8859-9 (Turkish)"),
        SubtitleEncodingOption(id: "gb18030", displayName: "GB18030 (Chinese)"),
        SubtitleEncodingOption(id: "gbk", displayName: "GBK (Simplified Chinese)"),
        SubtitleEncodingOption(id: "big5", displayName: "Big5 (Traditional Chinese)"),
        SubtitleEncodingOption(id: "shift_jis", displayName: "Shift_JIS (Japanese)"),
        SubtitleEncodingOption(id: "euc-jp", displayName: "EUC-JP (Japanese)"),
        SubtitleEncodingOption(id: "euc-kr", displayName: "EUC-KR (Korean)"),
        SubtitleEncodingOption(id: "koi8-r", displayName: "KOI8-R (Cyrillic)")
    ]

    public static func encoding(id: String) -> SubtitleEncodingOption {
        encodings.first(where: { $0.id == id }) ?? encodings[0]
    }
}

public struct KinemaPreferences: Sendable {
    public static let volumeMax: Double = 200

    public var volume: Double
    public var isMuted: Bool
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

    public var subtitleBorderSize: Double
    public var subtitleBorderColorHex: String
    public var subtitleShadowOffset: Double
    public var subtitleShadowColorHex: String
    public var subtitleBackColorHex: String
    public var subtitleBold: Bool
    public var subtitleItalic: Bool
    public var subtitlePos: Int
    public var secondarySubtitlePos: Int
    public var subtitleAlignX: SubtitleHorizontalAlign
    public var subtitleAlignY: SubtitleVerticalAlign
    public var secondarySubtitleAlignX: SubtitleHorizontalAlign
    public var subtitleASSOverride: SubtitleASSOverrideMode
    public var subtitleFadeOut: Bool
    public var preferredSubtitleLanguage: String
    public var preferSDHSubtitles: Bool
    public var forcedSubtitlesOnly: Bool
    public var wifiSharingEnabled: Bool
    public var wifiSharingPasscode: String
    public var wifiSharingPreferIPv6: Bool

    // MARK: Audio
    public var preferredAudioLanguage: String
    public var replayGain: AudioReplayGainMode
    public var audioOutputModule: AudioOutputModule
    public var audioOutputDeviceID: String
    public var audioVisualizationEnabled: Bool
    public var audioEqualizerEnabled: Bool
    public var audioEqualizerPresetID: String
    public var audioEqualizerBands: [Double]
    public var audioEqualizerPreamp: Double
    public var audioNormalizeEnabled: Bool
    public var audioCompressorEnabled: Bool
    public var audioCompressorThreshold: Double
    public var audioCompressorRatio: Double
    public var audioCompressorAttack: Double
    public var audioCompressorRelease: Double
    public var audioCompressorMakeup: Double
    public var audioChannelMode: AudioChannelMode
    public var audioStereoWidenerEnabled: Bool
    public var audioStereoWidenerAmount: Double
    public var audioHeadphoneVirtualizer: Bool
    public var audioForceMono: Bool
    public var audioPitchScale: Double
    public var audioSpatializerEnabled: Bool
    public var audioSpatializerAmount: Double

    public init(
        volume: Double = 100,
        isMuted: Bool = false,
        speed: Double = 1,
        resumePlayback: Bool = true,
        autoLoadSubtitles: Bool = true,
        subtitleFontSize: Int = 55,
        subtitleFontID: String = SubtitlePreferenceCatalog.defaultFontID,
        subtitleColorHex: String = SubtitlePreferenceCatalog.defaultColorHex,
        subtitleEncodingID: String = SubtitlePreferenceCatalog.defaultEncodingID,
        hardwareDecoding: Bool = true,
        musicModeEnabled: Bool = false,
        subtitleBorderSize: Double = 2,
        subtitleBorderColorHex: String = SubtitlePreferenceCatalog.defaultBorderColorHex,
        subtitleShadowOffset: Double = 1,
        subtitleShadowColorHex: String = SubtitlePreferenceCatalog.defaultShadowColorHex,
        subtitleBackColorHex: String = SubtitlePreferenceCatalog.defaultBackColorHex,
        subtitleBold: Bool = false,
        subtitleItalic: Bool = false,
        subtitlePos: Int = 100,
        secondarySubtitlePos: Int = 10,
        subtitleAlignX: SubtitleHorizontalAlign = .center,
        subtitleAlignY: SubtitleVerticalAlign = .bottom,
        secondarySubtitleAlignX: SubtitleHorizontalAlign = .center,
        subtitleASSOverride: SubtitleASSOverrideMode = .scale,
        subtitleFadeOut: Bool = false,
        preferredSubtitleLanguage: String = "en",
        preferSDHSubtitles: Bool = false,
        forcedSubtitlesOnly: Bool = false,
        wifiSharingEnabled: Bool = false,
        wifiSharingPasscode: String = "",
        wifiSharingPreferIPv6: Bool = true,
        preferredAudioLanguage: String = "en",
        replayGain: AudioReplayGainMode = .off,
        audioOutputModule: AudioOutputModule = .auto,
        audioOutputDeviceID: String = "",
        audioVisualizationEnabled: Bool = false,
        audioEqualizerEnabled: Bool = false,
        audioEqualizerPresetID: String = AudioEqualizerCatalog.flatID,
        audioEqualizerBands: [Double] = Array(repeating: 0, count: 10),
        audioEqualizerPreamp: Double = 0,
        audioNormalizeEnabled: Bool = false,
        audioCompressorEnabled: Bool = false,
        audioCompressorThreshold: Double = -20,
        audioCompressorRatio: Double = 3,
        audioCompressorAttack: Double = 20,
        audioCompressorRelease: Double = 250,
        audioCompressorMakeup: Double = 2,
        audioChannelMode: AudioChannelMode = .stereo,
        audioStereoWidenerEnabled: Bool = false,
        audioStereoWidenerAmount: Double = 2.5,
        audioHeadphoneVirtualizer: Bool = false,
        audioForceMono: Bool = false,
        audioPitchScale: Double = 1,
        audioSpatializerEnabled: Bool = false,
        audioSpatializerAmount: Double = 0.35
    ) {
        self.volume = min(Self.volumeMax, max(0, volume))
        self.isMuted = isMuted
        self.speed = speed
        self.resumePlayback = resumePlayback
        self.autoLoadSubtitles = autoLoadSubtitles
        self.subtitleFontSize = subtitleFontSize
        self.subtitleFontID = subtitleFontID
        self.subtitleColorHex = subtitleColorHex
        self.subtitleEncodingID = subtitleEncodingID
        self.hardwareDecoding = hardwareDecoding
        self.musicModeEnabled = musicModeEnabled
        self.subtitleBorderSize = subtitleBorderSize
        self.subtitleBorderColorHex = subtitleBorderColorHex
        self.subtitleShadowOffset = subtitleShadowOffset
        self.subtitleShadowColorHex = subtitleShadowColorHex
        self.subtitleBackColorHex = subtitleBackColorHex
        self.subtitleBold = subtitleBold
        self.subtitleItalic = subtitleItalic
        self.subtitlePos = subtitlePos
        self.secondarySubtitlePos = secondarySubtitlePos
        self.subtitleAlignX = subtitleAlignX
        self.subtitleAlignY = subtitleAlignY
        self.secondarySubtitleAlignX = secondarySubtitleAlignX
        self.subtitleASSOverride = subtitleASSOverride
        self.subtitleFadeOut = subtitleFadeOut
        self.preferredSubtitleLanguage = preferredSubtitleLanguage
        self.preferSDHSubtitles = preferSDHSubtitles
        self.forcedSubtitlesOnly = forcedSubtitlesOnly
        self.wifiSharingEnabled = wifiSharingEnabled
        self.wifiSharingPasscode = wifiSharingPasscode
        self.wifiSharingPreferIPv6 = wifiSharingPreferIPv6
        self.preferredAudioLanguage = preferredAudioLanguage
        self.replayGain = replayGain
        self.audioOutputModule = audioOutputModule
        self.audioOutputDeviceID = audioOutputDeviceID
        self.audioVisualizationEnabled = audioVisualizationEnabled
        self.audioEqualizerEnabled = audioEqualizerEnabled
        self.audioEqualizerPresetID = audioEqualizerPresetID
        self.audioEqualizerBands = AudioEqualizerCatalog.normalizedBands(audioEqualizerBands)
        self.audioEqualizerPreamp = min(20, max(-20, audioEqualizerPreamp))
        self.audioNormalizeEnabled = audioNormalizeEnabled
        self.audioCompressorEnabled = audioCompressorEnabled
        self.audioCompressorThreshold = audioCompressorThreshold
        self.audioCompressorRatio = audioCompressorRatio
        self.audioCompressorAttack = audioCompressorAttack
        self.audioCompressorRelease = audioCompressorRelease
        self.audioCompressorMakeup = audioCompressorMakeup
        self.audioChannelMode = audioChannelMode
        self.audioStereoWidenerEnabled = audioStereoWidenerEnabled
        self.audioStereoWidenerAmount = audioStereoWidenerAmount
        self.audioHeadphoneVirtualizer = audioHeadphoneVirtualizer
        self.audioForceMono = audioForceMono
        self.audioPitchScale = min(1.5, max(0.5, audioPitchScale))
        self.audioSpatializerEnabled = audioSpatializerEnabled
        self.audioSpatializerAmount = audioSpatializerAmount
    }
}

@MainActor
@Observable
public final class PreferencesStore {
    public static let shared = PreferencesStore()

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let volume = "kinema.volume"
        static let isMuted = "kinema.isMuted"
        static let speed = "kinema.speed"
        static let resumePlayback = "kinema.resumePlayback"
        static let autoLoadSubtitles = "kinema.autoLoadSubtitles"
        static let subtitleFontSize = "kinema.subtitleFontSize"
        static let subtitleFontID = "kinema.subtitleFontID"
        static let subtitleColorHex = "kinema.subtitleColorHex"
        static let subtitleEncodingID = "kinema.subtitleEncodingID"
        static let hardwareDecoding = "kinema.hardwareDecoding"
        static let musicModeEnabled = "kinema.musicModeEnabled"
        static let subtitleBorderSize = "kinema.subtitleBorderSize"
        static let subtitleBorderColorHex = "kinema.subtitleBorderColorHex"
        static let subtitleShadowOffset = "kinema.subtitleShadowOffset"
        static let subtitleShadowColorHex = "kinema.subtitleShadowColorHex"
        static let subtitleBackColorHex = "kinema.subtitleBackColorHex"
        static let subtitleBold = "kinema.subtitleBold"
        static let subtitleItalic = "kinema.subtitleItalic"
        static let subtitlePos = "kinema.subtitlePos"
        static let secondarySubtitlePos = "kinema.secondarySubtitlePos"
        static let subtitleAlignX = "kinema.subtitleAlignX"
        static let subtitleAlignY = "kinema.subtitleAlignY"
        static let secondarySubtitleAlignX = "kinema.secondarySubtitleAlignX"
        static let subtitleASSOverride = "kinema.subtitleASSOverride"
        static let subtitleFadeOut = "kinema.subtitleFadeOut"
        static let preferredSubtitleLanguage = "kinema.preferredSubtitleLanguage"
        static let preferSDHSubtitles = "kinema.preferSDHSubtitles"
        static let forcedSubtitlesOnly = "kinema.forcedSubtitlesOnly"
        static let wifiSharingEnabled = "kinema.wifiSharingEnabled"
        static let wifiSharingPasscode = "kinema.wifiSharingPasscode"
        static let wifiSharingPreferIPv6 = "kinema.wifiSharingPreferIPv6"
        static let preferredAudioLanguage = "kinema.preferredAudioLanguage"
        static let replayGain = "kinema.replayGain"
        static let audioOutputModule = "kinema.audioOutputModule"
        static let audioOutputDeviceID = "kinema.audioOutputDeviceID"
        static let audioVisualizationEnabled = "kinema.audioVisualizationEnabled"
        static let audioEqualizerEnabled = "kinema.audioEqualizerEnabled"
        static let audioEqualizerPresetID = "kinema.audioEqualizerPresetID"
        static let audioEqualizerBands = "kinema.audioEqualizerBands"
        static let audioEqualizerPreamp = "kinema.audioEqualizerPreamp"
        static let audioNormalizeEnabled = "kinema.audioNormalizeEnabled"
        static let audioCompressorEnabled = "kinema.audioCompressorEnabled"
        static let audioCompressorThreshold = "kinema.audioCompressorThreshold"
        static let audioCompressorRatio = "kinema.audioCompressorRatio"
        static let audioCompressorAttack = "kinema.audioCompressorAttack"
        static let audioCompressorRelease = "kinema.audioCompressorRelease"
        static let audioCompressorMakeup = "kinema.audioCompressorMakeup"
        static let audioChannelMode = "kinema.audioChannelMode"
        static let audioStereoWidenerEnabled = "kinema.audioStereoWidenerEnabled"
        static let audioStereoWidenerAmount = "kinema.audioStereoWidenerAmount"
        static let audioHeadphoneVirtualizer = "kinema.audioHeadphoneVirtualizer"
        static let audioForceMono = "kinema.audioForceMono"
        static let audioPitchScale = "kinema.audioPitchScale"
        static let audioSpatializerEnabled = "kinema.audioSpatializerEnabled"
        static let audioSpatializerAmount = "kinema.audioSpatializerAmount"
    }

    public var preferences: KinemaPreferences {
        didSet { persist() }
    }

    private init() {
        _ = SubtitleFontRegistry.prepare()
        let storedFont = defaults.string(forKey: Keys.subtitleFontID) ?? SubtitlePreferenceCatalog.defaultFontID
        let storedBands = defaults.array(forKey: Keys.audioEqualizerBands) as? [Double]
        preferences = KinemaPreferences(
            volume: defaults.object(forKey: Keys.volume) as? Double ?? 100,
            isMuted: defaults.object(forKey: Keys.isMuted) as? Bool ?? false,
            speed: defaults.object(forKey: Keys.speed) as? Double ?? 1,
            resumePlayback: defaults.object(forKey: Keys.resumePlayback) as? Bool ?? true,
            autoLoadSubtitles: defaults.object(forKey: Keys.autoLoadSubtitles) as? Bool ?? true,
            subtitleFontSize: defaults.object(forKey: Keys.subtitleFontSize) as? Int ?? 55,
            subtitleFontID: SubtitleFontRegistry.migrateLegacyFontID(storedFont),
            subtitleColorHex: defaults.string(forKey: Keys.subtitleColorHex) ?? SubtitlePreferenceCatalog.defaultColorHex,
            subtitleEncodingID: defaults.string(forKey: Keys.subtitleEncodingID) ?? SubtitlePreferenceCatalog.defaultEncodingID,
            hardwareDecoding: defaults.object(forKey: Keys.hardwareDecoding) as? Bool ?? true,
            musicModeEnabled: defaults.object(forKey: Keys.musicModeEnabled) as? Bool ?? false,
            subtitleBorderSize: defaults.object(forKey: Keys.subtitleBorderSize) as? Double ?? 2,
            subtitleBorderColorHex: defaults.string(forKey: Keys.subtitleBorderColorHex) ?? SubtitlePreferenceCatalog.defaultBorderColorHex,
            subtitleShadowOffset: defaults.object(forKey: Keys.subtitleShadowOffset) as? Double ?? 1,
            subtitleShadowColorHex: defaults.string(forKey: Keys.subtitleShadowColorHex) ?? SubtitlePreferenceCatalog.defaultShadowColorHex,
            subtitleBackColorHex: defaults.string(forKey: Keys.subtitleBackColorHex) ?? SubtitlePreferenceCatalog.defaultBackColorHex,
            subtitleBold: defaults.object(forKey: Keys.subtitleBold) as? Bool ?? false,
            subtitleItalic: defaults.object(forKey: Keys.subtitleItalic) as? Bool ?? false,
            subtitlePos: defaults.object(forKey: Keys.subtitlePos) as? Int ?? 100,
            secondarySubtitlePos: defaults.object(forKey: Keys.secondarySubtitlePos) as? Int ?? 10,
            subtitleAlignX: SubtitleHorizontalAlign(rawValue: defaults.string(forKey: Keys.subtitleAlignX) ?? "center") ?? .center,
            subtitleAlignY: SubtitleVerticalAlign(rawValue: defaults.string(forKey: Keys.subtitleAlignY) ?? "bottom") ?? .bottom,
            secondarySubtitleAlignX: SubtitleHorizontalAlign(rawValue: defaults.string(forKey: Keys.secondarySubtitleAlignX) ?? "center") ?? .center,
            subtitleASSOverride: SubtitleASSOverrideMode(rawValue: defaults.string(forKey: Keys.subtitleASSOverride) ?? "scale") ?? .scale,
            subtitleFadeOut: defaults.object(forKey: Keys.subtitleFadeOut) as? Bool ?? false,
            preferredSubtitleLanguage: defaults.string(forKey: Keys.preferredSubtitleLanguage) ?? "en",
            preferSDHSubtitles: defaults.object(forKey: Keys.preferSDHSubtitles) as? Bool ?? false,
            forcedSubtitlesOnly: defaults.object(forKey: Keys.forcedSubtitlesOnly) as? Bool ?? false,
            wifiSharingEnabled: defaults.object(forKey: Keys.wifiSharingEnabled) as? Bool ?? false,
            wifiSharingPasscode: defaults.string(forKey: Keys.wifiSharingPasscode) ?? "",
            wifiSharingPreferIPv6: defaults.object(forKey: Keys.wifiSharingPreferIPv6) as? Bool ?? true,
            preferredAudioLanguage: defaults.string(forKey: Keys.preferredAudioLanguage) ?? "en",
            replayGain: AudioReplayGainMode(rawValue: defaults.string(forKey: Keys.replayGain) ?? "off") ?? .off,
            audioOutputModule: AudioOutputModule(rawValue: defaults.string(forKey: Keys.audioOutputModule) ?? "auto") ?? .auto,
            audioOutputDeviceID: defaults.string(forKey: Keys.audioOutputDeviceID) ?? "",
            audioVisualizationEnabled: defaults.object(forKey: Keys.audioVisualizationEnabled) as? Bool ?? false,
            audioEqualizerEnabled: defaults.object(forKey: Keys.audioEqualizerEnabled) as? Bool ?? false,
            audioEqualizerPresetID: defaults.string(forKey: Keys.audioEqualizerPresetID) ?? AudioEqualizerCatalog.flatID,
            audioEqualizerBands: storedBands ?? Array(repeating: 0, count: 10),
            audioEqualizerPreamp: defaults.object(forKey: Keys.audioEqualizerPreamp) as? Double ?? 0,
            audioNormalizeEnabled: defaults.object(forKey: Keys.audioNormalizeEnabled) as? Bool ?? false,
            audioCompressorEnabled: defaults.object(forKey: Keys.audioCompressorEnabled) as? Bool ?? false,
            audioCompressorThreshold: defaults.object(forKey: Keys.audioCompressorThreshold) as? Double ?? -20,
            audioCompressorRatio: defaults.object(forKey: Keys.audioCompressorRatio) as? Double ?? 3,
            audioCompressorAttack: defaults.object(forKey: Keys.audioCompressorAttack) as? Double ?? 20,
            audioCompressorRelease: defaults.object(forKey: Keys.audioCompressorRelease) as? Double ?? 250,
            audioCompressorMakeup: defaults.object(forKey: Keys.audioCompressorMakeup) as? Double ?? 2,
            audioChannelMode: AudioChannelMode(rawValue: defaults.string(forKey: Keys.audioChannelMode) ?? "stereo") ?? .stereo,
            audioStereoWidenerEnabled: defaults.object(forKey: Keys.audioStereoWidenerEnabled) as? Bool ?? false,
            audioStereoWidenerAmount: defaults.object(forKey: Keys.audioStereoWidenerAmount) as? Double ?? 2.5,
            audioHeadphoneVirtualizer: defaults.object(forKey: Keys.audioHeadphoneVirtualizer) as? Bool ?? false,
            audioForceMono: defaults.object(forKey: Keys.audioForceMono) as? Bool ?? false,
            audioPitchScale: defaults.object(forKey: Keys.audioPitchScale) as? Double ?? 1,
            audioSpatializerEnabled: defaults.object(forKey: Keys.audioSpatializerEnabled) as? Bool ?? false,
            audioSpatializerAmount: defaults.object(forKey: Keys.audioSpatializerAmount) as? Double ?? 0.35
        )
    }

    private func persist() {
        defaults.set(preferences.volume, forKey: Keys.volume)
        defaults.set(preferences.isMuted, forKey: Keys.isMuted)
        defaults.set(preferences.speed, forKey: Keys.speed)
        defaults.set(preferences.resumePlayback, forKey: Keys.resumePlayback)
        defaults.set(preferences.autoLoadSubtitles, forKey: Keys.autoLoadSubtitles)
        defaults.set(preferences.subtitleFontSize, forKey: Keys.subtitleFontSize)
        defaults.set(preferences.subtitleFontID, forKey: Keys.subtitleFontID)
        defaults.set(preferences.subtitleColorHex, forKey: Keys.subtitleColorHex)
        defaults.set(preferences.subtitleEncodingID, forKey: Keys.subtitleEncodingID)
        defaults.set(preferences.hardwareDecoding, forKey: Keys.hardwareDecoding)
        defaults.set(preferences.musicModeEnabled, forKey: Keys.musicModeEnabled)
        defaults.set(preferences.subtitleBorderSize, forKey: Keys.subtitleBorderSize)
        defaults.set(preferences.subtitleBorderColorHex, forKey: Keys.subtitleBorderColorHex)
        defaults.set(preferences.subtitleShadowOffset, forKey: Keys.subtitleShadowOffset)
        defaults.set(preferences.subtitleShadowColorHex, forKey: Keys.subtitleShadowColorHex)
        defaults.set(preferences.subtitleBackColorHex, forKey: Keys.subtitleBackColorHex)
        defaults.set(preferences.subtitleBold, forKey: Keys.subtitleBold)
        defaults.set(preferences.subtitleItalic, forKey: Keys.subtitleItalic)
        defaults.set(preferences.subtitlePos, forKey: Keys.subtitlePos)
        defaults.set(preferences.secondarySubtitlePos, forKey: Keys.secondarySubtitlePos)
        defaults.set(preferences.subtitleAlignX.rawValue, forKey: Keys.subtitleAlignX)
        defaults.set(preferences.subtitleAlignY.rawValue, forKey: Keys.subtitleAlignY)
        defaults.set(preferences.secondarySubtitleAlignX.rawValue, forKey: Keys.secondarySubtitleAlignX)
        defaults.set(preferences.subtitleASSOverride.rawValue, forKey: Keys.subtitleASSOverride)
        defaults.set(preferences.subtitleFadeOut, forKey: Keys.subtitleFadeOut)
        defaults.set(preferences.preferredSubtitleLanguage, forKey: Keys.preferredSubtitleLanguage)
        defaults.set(preferences.preferSDHSubtitles, forKey: Keys.preferSDHSubtitles)
        defaults.set(preferences.forcedSubtitlesOnly, forKey: Keys.forcedSubtitlesOnly)
        defaults.set(preferences.wifiSharingEnabled, forKey: Keys.wifiSharingEnabled)
        defaults.set(preferences.wifiSharingPasscode, forKey: Keys.wifiSharingPasscode)
        defaults.set(preferences.wifiSharingPreferIPv6, forKey: Keys.wifiSharingPreferIPv6)
        defaults.set(preferences.preferredAudioLanguage, forKey: Keys.preferredAudioLanguage)
        defaults.set(preferences.replayGain.rawValue, forKey: Keys.replayGain)
        defaults.set(preferences.audioOutputModule.rawValue, forKey: Keys.audioOutputModule)
        defaults.set(preferences.audioOutputDeviceID, forKey: Keys.audioOutputDeviceID)
        defaults.set(preferences.audioVisualizationEnabled, forKey: Keys.audioVisualizationEnabled)
        defaults.set(preferences.audioEqualizerEnabled, forKey: Keys.audioEqualizerEnabled)
        defaults.set(preferences.audioEqualizerPresetID, forKey: Keys.audioEqualizerPresetID)
        defaults.set(preferences.audioEqualizerBands, forKey: Keys.audioEqualizerBands)
        defaults.set(preferences.audioEqualizerPreamp, forKey: Keys.audioEqualizerPreamp)
        defaults.set(preferences.audioNormalizeEnabled, forKey: Keys.audioNormalizeEnabled)
        defaults.set(preferences.audioCompressorEnabled, forKey: Keys.audioCompressorEnabled)
        defaults.set(preferences.audioCompressorThreshold, forKey: Keys.audioCompressorThreshold)
        defaults.set(preferences.audioCompressorRatio, forKey: Keys.audioCompressorRatio)
        defaults.set(preferences.audioCompressorAttack, forKey: Keys.audioCompressorAttack)
        defaults.set(preferences.audioCompressorRelease, forKey: Keys.audioCompressorRelease)
        defaults.set(preferences.audioCompressorMakeup, forKey: Keys.audioCompressorMakeup)
        defaults.set(preferences.audioChannelMode.rawValue, forKey: Keys.audioChannelMode)
        defaults.set(preferences.audioStereoWidenerEnabled, forKey: Keys.audioStereoWidenerEnabled)
        defaults.set(preferences.audioStereoWidenerAmount, forKey: Keys.audioStereoWidenerAmount)
        defaults.set(preferences.audioHeadphoneVirtualizer, forKey: Keys.audioHeadphoneVirtualizer)
        defaults.set(preferences.audioForceMono, forKey: Keys.audioForceMono)
        defaults.set(preferences.audioPitchScale, forKey: Keys.audioPitchScale)
        defaults.set(preferences.audioSpatializerEnabled, forKey: Keys.audioSpatializerEnabled)
        defaults.set(preferences.audioSpatializerAmount, forKey: Keys.audioSpatializerAmount)
    }

    public func mpvOptions() -> [String: String] {
        let fontsDir = SubtitleFontRegistry.prepare()
        let selectedFont = SubtitleFontRegistry.resolveStoredFontSelection(preferences.subtitleFontID)
        let p = preferences

        var options: [String: String] = [
            "volume": "\(Int(p.volume))",
            "volume-max": "\(Int(KinemaPreferences.volumeMax))",
            "mute": p.isMuted ? "yes" : "no",
            "speed": "\(p.speed)",
            "replaygain": p.replayGain.mpvValue,
            "sub-font-size": "\(p.subtitleFontSize)",
            "sub-color": normalizedSubtitleColorHex(p.subtitleColorHex),
            "sub-border-size": "\(p.subtitleBorderSize)",
            "sub-border-color": normalizedSubtitleColorHex(p.subtitleBorderColorHex),
            "sub-shadow-offset": "\(p.subtitleShadowOffset)",
            "sub-shadow-color": normalizedSubtitleColorHex(p.subtitleShadowColorHex),
            "sub-back-color": normalizedSubtitleColorHex(p.subtitleBackColorHex),
            "sub-bold": p.subtitleBold ? "yes" : "no",
            "sub-italic": p.subtitleItalic ? "yes" : "no",
            "sub-pos": "\(p.subtitlePos)",
            "secondary-sub-pos": "\(p.secondarySubtitlePos)",
            "sub-align-x": p.subtitleAlignX.rawValue,
            "sub-align-y": p.subtitleAlignY.rawValue,
            "sub-ass-override": p.subtitleASSOverride == .force ? "scale" : p.subtitleASSOverride.rawValue,
            "sub-codepage": SubtitlePreferenceCatalog.encoding(id: p.subtitleEncodingID).id,
            "keep-open": "yes",
            "hr-seek": "yes"
        ]

        let alang = p.preferredAudioLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        if !alang.isEmpty {
            options["alang"] = alang
        }
        if let ao = p.audioOutputModule.mpvAO {
            options["ao"] = ao
        }
        let device = p.audioOutputDeviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !device.isEmpty {
            options["audio-device"] = device
        }
        if let af = AudioFilterGraph.build(from: p) {
            options["af"] = af
        }

        // Do NOT set secondary-sub-align-x / secondary-sub-ass-override here —
        // older bundled libmpv rejects them and used to break startup.

        if let forceStyle = SubtitleASSForceStyleBuilder.build(from: p) {
            options["sub-ass-force-style"] = forceStyle
        }

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

public enum SubtitleASSForceStyleBuilder {
    /// Builds ASS force-style from live prefs.
    /// Never sets Alignment — that stays in the script (needed for dual L/R).
    public static func build(
        from preferences: KinemaPreferences,
        alwaysApplyLook: Bool = false
    ) -> String? {
        let mode = preferences.subtitleASSOverride
        let applyLook = alwaysApplyLook
            || mode == .force
            || mode == .yes
            || mode == .scale
        guard applyLook else { return nil }

        var parts: [String] = []
        let font = SubtitleFontRegistry.resolveStoredFontSelection(preferences.subtitleFontID)
        if !font.mpvFontName.isEmpty {
            parts.append("Fontname=\(font.mpvFontName)")
        }
        parts.append("Fontsize=\(preferences.subtitleFontSize)")
        parts.append("PrimaryColour=\(assColor(from: preferences.subtitleColorHex))")
        parts.append("OutlineColour=\(assColor(from: preferences.subtitleBorderColorHex))")
        parts.append("BackColour=\(assColor(from: preferences.subtitleBackColorHex))")
        parts.append("Bold=\(preferences.subtitleBold ? -1 : 0)")
        parts.append("Italic=\(preferences.subtitleItalic ? -1 : 0)")
        parts.append("Outline=\(String(format: "%.2f", max(0, preferences.subtitleBorderSize)))")
        parts.append("Shadow=\(String(format: "%.2f", max(0, preferences.subtitleShadowOffset)))")
        let backOpacity = subtitleColorOpacity(normalizedSubtitleColorHex(preferences.subtitleBackColorHex))
        parts.append("BorderStyle=\(backOpacity > 0.04 ? 3 : 1)")
        if preferences.subtitleFadeOut {
            parts.append("Blur=0.4")
        }
        return parts.joined(separator: ",")
    }

    private static func assColor(from hex: String) -> String {
        var value = normalizedSubtitleColorHex(hex)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 8 else { return "&H00FFFFFF" }
        let aa = String(value.prefix(2))
        let rr = String(value.dropFirst(2).prefix(2))
        let gg = String(value.dropFirst(4).prefix(2))
        let bb = String(value.dropFirst(6).prefix(2))
        return "&H\(aa)\(bb)\(gg)\(rr)"
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

public func subtitleColorOpacity(_ hex: String) -> Double {
    var value = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    if value.hasPrefix("#") { value.removeFirst() }
    guard value.count == 8, let alpha = Int(value.prefix(2), radix: 16) else { return 1 }
    return Double(alpha) / 255.0
}

public func applyingSubtitleOpacity(_ hex: String, opacity: Double) -> String {
    var value = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    if value.hasPrefix("#") { value.removeFirst() }
    let rgb: String
    switch value.count {
    case 6: rgb = value
    case 8: rgb = String(value.suffix(6))
    default: rgb = "FFFFFF"
    }
    let clamped = max(0, min(1, opacity))
    let alpha = Int((clamped * 255).rounded())
    return String(format: "#%02X%@", alpha, rgb)
}
