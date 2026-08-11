import Foundation

/// Kinema voice & vocabulary — warm, cinematic, personal.
/// κίνημα · motion · your cinema.
public enum KinemaCopy {
    // MARK: - Brand

    public static let appName = "Kinema"
    public static let tagline = "Your cinema"

    // MARK: - Main destinations

    public static let collection = "Collection"
    public static let `continue` = "Continue"

    // MARK: - Collection / sources

    public static let allSources = "All Sources"
    public static let sources = "Sources"
    public static let yourSources = "Your Sources"
    public static let addSource = "Add Source"
    public static let addFirstSource = "Add Your First Source"
    public static let addSourceHint = "Pick a folder from Files, iCloud Drive, or anywhere on your device."
    public static let addSourceTileSubtitle = "Bring in a folder from your device"

    public static let collectionIntroTitle = "Your Sources"
    public static let collectionIntroBody =
        "Your Kinema library is always here. Add more folders from Files, iCloud Drive, or anywhere on your device — with smart spotlights for series."

    public static let backToCollection = "Collection"

    public static let removeSource = "Remove Source"
    public static let removeSourceTitle = "Remove Source?"
    public static let removeSourceMessage =
        "This removes the source from your collection. Your files stay on disk."

    public static let savedSource = "Saved source"
    public static let onThisDevice = "On This Device"
    public static let builtInSourceSubtitle = "On this device · Finder & Files ready"
    public static let builtInSourceBadge = "Built-in"
    public static let revealInFinder = "Reveal in Finder"
    public static let newFolder = "New Folder"
    public static let newFolderPrompt = "Enter a name for the folder."
    public static let rescan = "Rescan"
    public static let playFolder = "Play Folder"
    public static let searchLibrary = "Search library"
    public static let wifiSharing = "Wi‑Fi Sharing"
    public static let wifiSharingSubtitle = "Upload and download media from a computer on the same network."
    public static let wifiSharingPasscode = "Passcode"
    public static let wifiSharingPasscodeHint = "Optional. Username is kinema."
    public static let wifiSharingPreferIPv6 = "Prefer IPv6 addresses"
    public static let wifiSharingURL = "Sharing address"
    public static let copyURL = "Copy Address"
    public static let downloadToLibrary = "Download to Library"
    public static let downloadStarted = "Download started"
    public static let downloadFailed = "Download failed"

    // MARK: - Content sections

    public static let folders = "Folders"
    public static let spotlights = "Spotlights"
    public static let foldersAndSpotlights = "Folders & Spotlights"
    public static let titles = "Titles"
    public static let spotlightBadge = "Kinema Spotlight"

    // MARK: - Empty states

    public static let noSourcesTitle = "No extra sources yet"
    public static let noSourcesMessage =
        "Your built-in Kinema library is ready. Add another folder anytime."

    public static let nothingHereTitle = "Nothing here yet"
    public static let nothingHereMessage =
        "This location is empty. Try another folder in your collection, or add a new source."

    public static let builtInEmptyTitle = "Your Kinema library is empty"
    public static let builtInEmptyMessage: String = {
        #if os(macOS)
        return "Drop videos into this library from Finder, turn on Wi‑Fi Sharing in Preferences to upload from another computer, or download a stream into Kinema. Files you add here stay on this Mac."
        #elseif os(tvOS)
        return "Turn on Wi‑Fi Sharing in Preferences to upload videos from a computer on the same network, or download a stream into Kinema. Files you add here live in this library."
        #else
        return "Add videos with the Files app (On My iPhone / iPad → Kinema), AirDrop, Wi‑Fi Sharing in Preferences, or Download to Library from Stream. Everything here stays on this device."
        #endif
    }()

    public static let nothingInSpotlightTitle = "No titles in this spotlight"
    public static let nothingInSpotlightMessage =
        "Go back to explore more from this source."

    public static let nothingToContinueTitle = "Nothing to continue"
    public static let nothingToContinueMessage =
        "Titles you watch will appear here so you can pick up where you left off."

    // MARK: - Open / import

    public static let openSection = "Open"
    public static let openFiles = "Open Files"
    public static let openStream = "Open Stream"
    public static let openStreamTitle = "Stream"
    public static let openStreamHint =
        "Paste a direct video URL, network stream, or Kinema link — and press play."
    public static let openStreamHeroSubtitle =
        "Bring in a stream without adding a source. Valid titles land in Continue when they play."
    public static let openStreamFieldLabel = "Link"
    public static let openStreamPlaceholder = "https://… or kinema://…"
    public static let openStreamPlay = "Play Stream"

    // MARK: - Player

    public static let lineup = "Lineup"
    public static let preferences = "Preferences"
    public static let audio = "Audio"
    public static let chapters = "Chapters"
    public static let chaptersNoneAvailable = "This title has no chapters."
    public static let abLoop = "A–B Loop"
    public static let picture = "Picture"
    public static let pictureFit = "Fit"
    public static let pictureFill = "Fill"
    public static let pictureStretch = "Stretch"
    public static let pictureZoomIn = "Zoom In"
    public static let pictureZoomOut = "Zoom Out"
    public static let pictureRotate = "Rotate 90°"
    public static let pictureReset = "Reset Picture"
    public static let keyboardShortcuts = "Keyboard Shortcuts"
    public static let keyboardRecord = "Press a key…"
    public static let keyboardAddKey = "Add key"
    public static let keyboardReset = "Reset"
    public static let keyboardResetAll = "Reset all shortcuts"
    public static let keyboardConflictPrefix = "Moved from"
    public static let upNext = "Up Next"
    public static let upNextPlayingIn = "Playing in"
    public static let upNextPlayNow = "Play Now"
    public static let upNextCancel = "Not now"
    public static let upNextSettingsSubtitle =
        "During the closing moments of a series episode, offer the next title with a short countdown. Skipping ahead marks the current episode watched."
    public static let hdrToneMapping = "HDR tone mapping"
    public static let hdrToneMappingSubtitle =
        "Map HDR video for typical displays. Force uses a stronger curve; Off hard-clips highlights."
    public static let hdrTargetPeak = "HDR target peak"
    public static let captions = "Subtitles"
    public static let captionsOff = "Off"
    public static let captionsEmbedded = "In this video"
    public static let captionsSidecar = "Sidecar files"
    public static let captionsBrowse = "Browse for subtitle file…"
    public static let captionsNoneAvailable = "No subtitles for this title yet."
    public static let captionsNowPlaying = "Now showing"
    public static let captionsSize = "Font size"
    public static let captionsFont = "Font"
    public static let captionsColor = "Color"
    public static let captionsEncoding = "Text encoding"
    public static let captionsSearchOnline = "Search online"
    public static let captionsAutoLoad = "Auto-load subtitles"
    public static let captionsAutoLoadSubtitle =
        "Turn on embedded subtitles or matching sidecar files when a title starts."

    // MARK: - Actions

    public static let done = "Done"
    public static let cancel = "Cancel"
    public static let rename = "Rename"
    public static let delete = "Delete"
    public static let play = "Play"
    public static let open = "Open"
    public static let up = "Up"

    public static let markWatched = "Mark as Watched"
    public static let markUnwatched = "Mark as Unwatched"
    public static let markAllWatched = "Mark All as Watched"
    public static let markAllUnwatched = "Mark All as Unwatched"
    public static let markedWatched = "Marked as watched"
    public static let markedUnwatched = "Marked as unwatched"
    public static let markedAllWatched = "Marked all as watched"
    public static let markedAllUnwatched = "Marked all as unwatched"
    public static let couldNotMarkWatched = "Couldn't determine duration"
    public static let folderWatched = "Watched"

    public static let renamePrompt = "Enter a new display name."
    public static let deleteFileTitle = "Delete File?"
    public static let deleteFileMessage = "This removes the file from disk."
}
