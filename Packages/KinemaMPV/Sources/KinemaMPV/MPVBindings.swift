import Foundation

/// Curated mpv properties used by Kinema.
public enum MPVProperty: String, Sendable {
    case pause = "pause"
    case timePos = "time-pos"
    case duration = "duration"
    case volume = "volume"
    case speed = "speed"
    case filename = "filename"
    case mediaTitle = "media-title"
    case trackList = "track-list"
    case chapterList = "chapter-list"
    case chapter = "chapter"
    case sid = "sid"
    case secondarySid = "secondary-sid"
    case subDelay = "sub-delay"
    case secondarySubDelay = "secondary-sub-delay"
    case secondarySubText = "secondary-sub-text"
    case secondarySubVisibility = "secondary-sub-visibility"
    case audioDelay = "audio-delay"
    case mute = "mute"
    case aid = "aid"
    case af = "af"
    case replaygain = "replaygain"
    case audioDevice = "audio-device"
    case audioDeviceList = "audio-device-list"
    case eofReached = "eof-reached"
    case idleActive = "idle-active"
    case coreIdle = "core-idle"
    case videoParams = "video-params"
    case audioParams = "audio-params"
}

/// Curated mpv commands.
public enum MPVCommand: String, Sendable {
    case loadfile
    case stop
    case quit
    case seek
    case cycle
    case set
    case showText = "show-text"
    case subAdd = "sub-add"
    case subRemove = "sub-remove"
    case subReload = "sub-reload"
    case playlistNext = "playlist-next"
    case playlistPrev = "playlist-prev"
}

/// Common mpv options applied at startup.
public enum MPVOption: String, Sendable {
    case vo = "vo"
    case hwdec = "hwdec"
    case keepOpen = "keep-open"
    case hrSeek = "hr-seek"
    case subAuto = "sub-auto"
    case subFont = "sub-font"
    case subFontSize = "sub-font-size"
    case subColor = "sub-color"
    case subCodepage = "sub-codepage"
    case subFontsDir = "sub-fonts-dir"
    case subBorderSize = "sub-border-size"
    case subBorderColor = "sub-border-color"
    case subShadowOffset = "sub-shadow-offset"
    case subShadowColor = "sub-shadow-color"
    case subBackColor = "sub-back-color"
    case subBold = "sub-bold"
    case subItalic = "sub-italic"
    case subPos = "sub-pos"
    case secondarySubPos = "secondary-sub-pos"
    case subAlignX = "sub-align-x"
    case subAlignY = "sub-align-y"
    case secondarySubAlignX = "secondary-sub-align-x"
    case secondarySubASSOverride = "secondary-sub-ass-override"
    case subSpeed = "sub-speed"
    case subASSOverride = "sub-ass-override"
    case subASSForceStyle = "sub-ass-force-style"
    case ytdl = "ytdl"
    case inputDefaultBindings = "input-default-bindings"
    case inputVideol = "input-vo-keyboard"
}
