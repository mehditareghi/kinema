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
        "Connect the folders you already use. Kinema turns them into your personal collection — with smart spotlights for series, and room for everything else."

    public static let backToCollection = "Collection"

    public static let removeSource = "Remove Source"
    public static let removeSourceTitle = "Remove Source?"
    public static let removeSourceMessage =
        "This removes the source from your collection. Your files stay on disk."

    public static let savedSource = "Saved source"

    // MARK: - Content sections

    public static let folders = "Folders"
    public static let spotlights = "Spotlights"
    public static let foldersAndSpotlights = "Folders & Spotlights"
    public static let titles = "Titles"
    public static let spotlightBadge = "Kinema Spotlight"

    // MARK: - Empty states

    public static let noSourcesTitle = "No sources yet"
    public static let noSourcesMessage = addSourceHint

    public static let nothingHereTitle = "Nothing here yet"
    public static let nothingHereMessage =
        "This location is empty. Try another folder in your collection, or add a new source."

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
    public static let markedWatched = "Marked as watched"
    public static let markedUnwatched = "Marked as unwatched"
    public static let couldNotMarkWatched = "Couldn't determine duration"
    public static let folderWatched = "Watched"

    public static let renamePrompt = "Enter a new display name."
    public static let deleteFileTitle = "Delete File?"
    public static let deleteFileMessage = "This removes the file from disk."
}
