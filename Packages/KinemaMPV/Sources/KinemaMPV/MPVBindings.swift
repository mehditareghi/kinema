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
    case sid = "sid"
    case mute = "mute"
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
    case ytdl = "ytdl"
    case inputDefaultBindings = "input-default-bindings"
    case inputVideol = "input-vo-keyboard"
}
