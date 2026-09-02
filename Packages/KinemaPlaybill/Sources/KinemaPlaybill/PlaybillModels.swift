import Foundation

public enum PlaybillMediaKind: String, Codable, Sendable {
    case movie
    case tvShow
    case episode
}

public enum WatchSource: String, Codable, Sendable {
    case player
    case manual
    case importTrakt
    case importBackup
}

public enum WatchCompletion: String, Codable, Sendable {
    case full
    case partial
}

public enum PlaybillEpisodeAvailability: Sendable, Equatable {
    case released
    case upcoming(Date)
    case unscheduled
    case unknown

    public var canMarkWatched: Bool {
        switch self {
        case .released, .unknown: true
        case .upcoming, .unscheduled: false
        }
    }
}

public enum MatchConfidence: String, Codable, Sendable, Equatable {
    case high
    case medium
    case manual
}

public struct CatalogEntry: Codable, Identifiable, Sendable, Equatable, Hashable {
    public var id: String
    public var kind: PlaybillMediaKind
    public var tmdbID: Int
    public var parentShowID: String?
    public var title: String
    public var subtitle: String?
    public var year: Int?
    public var overview: String?
    public var posterPath: String?
    public var backdropPath: String?
    public var genres: [String]
    public var runtimeMinutes: Int?
    public var seasonNumber: Int?
    public var episodeNumber: Int?
    /// The episode's TMDB air date. Kept separately from `year` so future
    /// episodes can be shown without being treated as watchable releases.
    public var episodeAirDate: Date? = nil
    public var cachedAt: Date
    /// TMDB lifecycle metadata for deriving series state without asking the viewer.
    public var seriesStatus: String? = nil
    public var seriesInProduction: Bool? = nil
    public var nextEpisodeAirDate: Date? = nil
    public var totalEpisodeCount: Int? = nil
    public var lastAiredSeasonNumber: Int? = nil
    public var lastAiredEpisodeNumber: Int? = nil
    /// The most recent episode air date reported by TMDB. This lets lifecycle
    /// repair distinguish an actively returning show from a years-old stale
    /// "Returning Series" flag.
    public var lastEpisodeAirDate: Date? = nil

    public init(
        id: String,
        kind: PlaybillMediaKind,
        tmdbID: Int,
        parentShowID: String? = nil,
        title: String,
        subtitle: String? = nil,
        year: Int? = nil,
        overview: String? = nil,
        posterPath: String? = nil,
        backdropPath: String? = nil,
        genres: [String] = [],
        runtimeMinutes: Int? = nil,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil,
        episodeAirDate: Date? = nil,
        cachedAt: Date = Date(),
        seriesStatus: String? = nil,
        seriesInProduction: Bool? = nil,
        nextEpisodeAirDate: Date? = nil,
        totalEpisodeCount: Int? = nil,
        lastAiredSeasonNumber: Int? = nil,
        lastAiredEpisodeNumber: Int? = nil,
        lastEpisodeAirDate: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.tmdbID = tmdbID
        self.parentShowID = parentShowID
        self.title = title
        self.subtitle = subtitle
        self.year = year
        self.overview = overview
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.genres = genres
        self.runtimeMinutes = runtimeMinutes
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.episodeAirDate = episodeAirDate
        self.cachedAt = cachedAt
        self.seriesStatus = seriesStatus
        self.seriesInProduction = seriesInProduction
        self.nextEpisodeAirDate = nextEpisodeAirDate
        self.totalEpisodeCount = totalEpisodeCount
        self.lastAiredSeasonNumber = lastAiredSeasonNumber
        self.lastAiredEpisodeNumber = lastAiredEpisodeNumber
        self.lastEpisodeAirDate = lastEpisodeAirDate
    }

    public var displayTitle: String {
        switch kind {
        case .episode:
            if let seasonNumber, let episodeNumber {
                let code = String(format: "S%02dE%02d", seasonNumber, episodeNumber)
                if let subtitle, !subtitle.isEmpty {
                    return "\(title) · \(code) · \(subtitle)"
                }
                return "\(title) · \(code)"
            }
            return title
        case .movie, .tvShow:
            if let year {
                return "\(title) (\(year))"
            }
            return title
        }
    }

    public static func movieID(_ tmdbID: Int) -> String { "tmdb:movie:\(tmdbID)" }
    public static func showID(_ tmdbID: Int) -> String { "tmdb:tv:\(tmdbID)" }
    public static func episodeID(showTmdbID: Int, season: Int, episode: Int) -> String {
        "tmdb:tv:\(showTmdbID):s\(season)e\(episode)"
    }
}

public struct WatchActivity: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var targetID: String
    public var watchedAt: Date
    public var source: WatchSource
    public var completion: WatchCompletion
    public var watchedSeconds: TimeInterval?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        targetID: String,
        watchedAt: Date = Date(),
        source: WatchSource,
        completion: WatchCompletion = .full,
        watchedSeconds: TimeInterval? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.targetID = targetID
        self.watchedAt = watchedAt
        self.source = source
        self.completion = completion
        self.watchedSeconds = watchedSeconds
        self.createdAt = createdAt
    }
}

public struct PlaybillWatchRemovalSnapshot: Sendable, Equatable {
    public var activities: [WatchActivity]
    public var playbackProgress: [String: TitlePlaybackProgress]

    public init(
        activities: [WatchActivity],
        playbackProgress: [String: TitlePlaybackProgress] = [:]
    ) {
        self.activities = activities
        self.playbackProgress = playbackProgress
    }

    public var isEmpty: Bool {
        activities.isEmpty && playbackProgress.isEmpty
    }
}

public struct MediaLink: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var mediaID: String
    public var targetID: String
    public var matchConfidence: MatchConfidence
    public var confirmedByUser: Bool
    public var linkedAt: Date

    public init(
        id: UUID = UUID(),
        mediaID: String,
        targetID: String,
        matchConfidence: MatchConfidence,
        confirmedByUser: Bool,
        linkedAt: Date = Date()
    ) {
        self.id = id
        self.mediaID = mediaID
        self.targetID = targetID
        self.matchConfidence = matchConfidence
        self.confirmedByUser = confirmedByUser
        self.linkedAt = linkedAt
    }
}

public struct ShowMatchMemory: Codable, Sendable, Equatable {
    public var showKey: String
    public var tmdbShowID: Int
    public var showTargetID: String
    public var confirmedAt: Date
}

public struct PlaybillDatabase: Codable, Sendable {
    public static let currentVersion = 8

    public var version: Int
    public var catalog: [String: CatalogEntry]
    public var activities: [WatchActivity]
    public var mediaLinks: [MediaLink]
    public var showMemories: [ShowMatchMemory]
    /// Latest in-progress playback per Playbill title (survives unlinked / newly added files).
    public var playbackProgress: [String: TitlePlaybackProgress]
    /// Series the user follows in Playbill (tracking ≠ watched).
    public var trackedShows: [TrackedShow]
    public var lists: [PlaybillList]
    public var listItems: [PlaybillListItem]
    /// Disk-backed episode maps used by Up Next and lifecycle derivation offline.
    public var showMetadataSnapshots: [String: PlaybillShowMetadataSnapshot]
    /// Completed watches whose local file has not been confidently identified yet.
    public var pendingWatchResolutions: [PendingWatchResolution]

    public init(
        version: Int = Self.currentVersion,
        catalog: [String: CatalogEntry] = [:],
        activities: [WatchActivity] = [],
        mediaLinks: [MediaLink] = [],
        showMemories: [ShowMatchMemory] = [],
        playbackProgress: [String: TitlePlaybackProgress] = [:],
        trackedShows: [TrackedShow] = [],
        lists: [PlaybillList] = [],
        listItems: [PlaybillListItem] = [],
        showMetadataSnapshots: [String: PlaybillShowMetadataSnapshot] = [:],
        pendingWatchResolutions: [PendingWatchResolution] = []
    ) {
        self.version = version
        self.catalog = catalog
        self.activities = activities
        self.mediaLinks = mediaLinks
        self.showMemories = showMemories
        self.playbackProgress = playbackProgress
        self.trackedShows = trackedShows
        self.lists = lists
        self.listItems = listItems
        self.showMetadataSnapshots = showMetadataSnapshots
        self.pendingWatchResolutions = pendingWatchResolutions
    }

    private enum CodingKeys: String, CodingKey {
        case version, catalog, activities, mediaLinks, showMemories, playbackProgress
        case trackedShows, lists, listItems, showMetadataSnapshots, pendingWatchResolutions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        catalog = try container.decodeIfPresent([String: CatalogEntry].self, forKey: .catalog) ?? [:]
        activities = try container.decodeIfPresent([WatchActivity].self, forKey: .activities) ?? []
        mediaLinks = try container.decodeIfPresent([MediaLink].self, forKey: .mediaLinks) ?? []
        showMemories = try container.decodeIfPresent([ShowMatchMemory].self, forKey: .showMemories) ?? []
        playbackProgress = try container.decodeIfPresent([String: TitlePlaybackProgress].self, forKey: .playbackProgress) ?? [:]
        trackedShows = try container.decodeIfPresent([TrackedShow].self, forKey: .trackedShows) ?? []
        lists = try container.decodeIfPresent([PlaybillList].self, forKey: .lists) ?? []
        listItems = try container.decodeIfPresent([PlaybillListItem].self, forKey: .listItems) ?? []
        showMetadataSnapshots = try container.decodeIfPresent(
            [String: PlaybillShowMetadataSnapshot].self,
            forKey: .showMetadataSnapshots
        ) ?? [:]
        pendingWatchResolutions = try container.decodeIfPresent(
            [PendingWatchResolution].self,
            forKey: .pendingWatchResolutions
        ) ?? []
    }
}

public struct TitlePlaybackProgress: Codable, Sendable, Equatable {
    public var position: TimeInterval
    public var duration: TimeInterval
    public var updatedAt: Date

    public init(position: TimeInterval, duration: TimeInterval, updatedAt: Date = Date()) {
        self.position = position
        self.duration = duration
        self.updatedAt = updatedAt
    }

    public var isMostlyFinished: Bool {
        duration > 0 && position >= duration - 10
    }

    public var hasPartialResume: Bool {
        duration > 0 && !isMostlyFinished && position > 5
    }

    public var fraction: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, position / duration))
    }
}

// MARK: - Offline-first metadata and watch resolution

public struct PlaybillCachedEpisode: Codable, Sendable, Equatable, Identifiable {
    public var episodeNumber: Int
    public var name: String
    public var airDate: Date?
    public var runtimeMinutes: Int?
    public var stillPath: String?

    public var id: Int { episodeNumber }

    public init(
        episodeNumber: Int,
        name: String,
        airDate: Date?,
        runtimeMinutes: Int?,
        stillPath: String?
    ) {
        self.episodeNumber = episodeNumber
        self.name = name
        self.airDate = airDate
        self.runtimeMinutes = runtimeMinutes
        self.stillPath = stillPath
    }
}

public struct PlaybillCachedSeason: Codable, Sendable, Equatable, Identifiable {
    public var seasonNumber: Int
    public var episodeCount: Int
    public var name: String?
    public var episodes: [PlaybillCachedEpisode]

    public var id: Int { seasonNumber }

    public init(
        seasonNumber: Int,
        episodeCount: Int,
        name: String?,
        episodes: [PlaybillCachedEpisode] = []
    ) {
        self.seasonNumber = seasonNumber
        self.episodeCount = episodeCount
        self.name = name
        self.episodes = episodes
    }
}

public struct PlaybillShowMetadataSnapshot: Codable, Sendable, Equatable {
    public var showTargetID: String
    public var tmdbShowID: Int
    public var seasons: [PlaybillCachedSeason]
    public var updatedAt: Date

    public init(
        showTargetID: String,
        tmdbShowID: Int,
        seasons: [PlaybillCachedSeason],
        updatedAt: Date = Date()
    ) {
        self.showTargetID = showTargetID
        self.tmdbShowID = tmdbShowID
        self.seasons = seasons
        self.updatedAt = updatedAt
    }

    public var hasCompleteEpisodeMap: Bool {
        let regularSeasons = seasons.filter { $0.seasonNumber > 0 }
        guard !regularSeasons.isEmpty else { return false }
        return regularSeasons.allSatisfy { season in
            season.episodeCount > 0 && season.episodes.count >= season.episodeCount
        }
    }
}

public struct PendingWatchResolution: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var mediaID: String
    public var mediaLocation: String
    public var mediaTitle: String
    public var parsedShowTitle: String?
    public var parsedSeason: Int?
    public var parsedEpisode: Int?
    public var watchedAt: Date
    public var source: WatchSource
    public var watchedSeconds: TimeInterval
    public var createdAt: Date
    public var retryCount: Int
    public var lastAttemptAt: Date?
    public var lastError: String?

    public init(
        id: UUID = UUID(),
        mediaID: String,
        mediaLocation: String,
        mediaTitle: String,
        parsedShowTitle: String? = nil,
        parsedSeason: Int? = nil,
        parsedEpisode: Int? = nil,
        watchedAt: Date = Date(),
        source: WatchSource,
        watchedSeconds: TimeInterval,
        createdAt: Date = Date(),
        retryCount: Int = 0,
        lastAttemptAt: Date? = nil,
        lastError: String? = nil
    ) {
        self.id = id
        self.mediaID = mediaID
        self.mediaLocation = mediaLocation
        self.mediaTitle = mediaTitle
        self.parsedShowTitle = parsedShowTitle
        self.parsedSeason = parsedSeason
        self.parsedEpisode = parsedEpisode
        self.watchedAt = watchedAt
        self.source = source
        self.watchedSeconds = watchedSeconds
        self.createdAt = createdAt
        self.retryCount = retryCount
        self.lastAttemptAt = lastAttemptAt
        self.lastError = lastError
    }
}

public struct PlaybillContinueItem: Identifiable, Sendable {
    public var id: String { entry.id }
    public let entry: CatalogEntry
    public let progress: TitlePlaybackProgress

    public init(entry: CatalogEntry, progress: TitlePlaybackProgress) {
        self.entry = entry
        self.progress = progress
    }
}

public struct PlaybillLocalMedia: Sendable, Equatable {
    public let url: URL
    public let title: String

    public init(url: URL, title: String) {
        self.url = url
        self.title = title
    }
}

public struct PlaybillDiaryItem: Identifiable, Sendable {
    public var id: UUID { activity.id }
    public let activity: WatchActivity
    public let entry: CatalogEntry

    public init(activity: WatchActivity, entry: CatalogEntry) {
        self.activity = activity
        self.entry = entry
    }
}

public struct PlaybillStatistics: Sendable {
    public var totalWatches: Int
    public var uniqueTitles: Int
    public var movieWatches: Int
    public var episodeWatches: Int
    public var rewatchCount: Int
    public var totalWatchedHours: Double
    public var watchesThisMonth: Int
    public var watchesThisYear: Int

    public static let empty = PlaybillStatistics(
        totalWatches: 0,
        uniqueTitles: 0,
        movieWatches: 0,
        episodeWatches: 0,
        rewatchCount: 0,
        totalWatchedHours: 0,
        watchesThisMonth: 0,
        watchesThisYear: 0
    )
}

public struct PlaybillSearchResult: Identifiable, Sendable, Hashable {
    public var id: String
    public var kind: PlaybillMediaKind
    public var tmdbID: Int
    public var title: String
    public var subtitle: String?
    public var year: Int?
    public var overview: String?
    public var posterPath: String?
}

public enum PlaybillTitleState: Sendable, Hashable {
    case new
    case tracked(TrackedShowStatus)
    case watched(count: Int)
    case watchLater

    public var isExisting: Bool {
        switch self {
        case .new: return false
        case .tracked, .watched, .watchLater: return true
        }
    }
}

public struct TraktImportSummary: Sendable, Equatable {
    public var added: Int
    public var alreadyPresent: Int
    public var repaired: Int

    public init(added: Int = 0, alreadyPresent: Int = 0, repaired: Int = 0) {
        self.added = added
        self.alreadyPresent = alreadyPresent
        self.repaired = repaired
    }

    public var handled: Int { added + alreadyPresent }
}

public struct PlaybillMatchCandidate: Identifiable, Sendable {
    public var id: String { result.id }
    public let result: PlaybillSearchResult
    public let confidence: MatchConfidence
}

public enum PlaybillMatchPromptPurpose: Sendable, Equatable {
    case identifyPlayback
    case logCompletedWatch
}

public struct PlaybillMatchPrompt: Identifiable, Sendable {
    public let id: UUID
    public let mediaURL: URL
    public let mediaTitle: String
    public let candidates: [PlaybillMatchCandidate]
    public let watchedSeconds: TimeInterval
    public let sessionKey: String
    public let watchedAt: Date
    public let pendingResolutionID: UUID?
    public let source: WatchSource
    public let purpose: PlaybillMatchPromptPurpose

    public init(
        id: UUID = UUID(),
        mediaURL: URL,
        mediaTitle: String,
        candidates: [PlaybillMatchCandidate],
        watchedSeconds: TimeInterval,
        sessionKey: String,
        watchedAt: Date = Date(),
        pendingResolutionID: UUID? = nil,
        source: WatchSource = .player,
        purpose: PlaybillMatchPromptPurpose = .logCompletedWatch
    ) {
        self.id = id
        self.mediaURL = mediaURL
        self.mediaTitle = mediaTitle
        self.candidates = candidates
        self.watchedSeconds = watchedSeconds
        self.sessionKey = sessionKey
        self.watchedAt = watchedAt
        self.pendingResolutionID = pendingResolutionID
        self.source = source
        self.purpose = purpose
    }
}

public enum PlaybillScrobbleResolution: Sendable {
    case autoLogged(targetID: String)
    case needsConfirmation([PlaybillMatchCandidate])
    case noMatch
}

// MARK: - Tracking & lists

public enum TrackedShowStatus: String, Codable, Sendable, Hashable {
    case watching
    case planToWatch
    /// All currently available episodes are watched, but the series is expected to continue.
    case waiting
    case completed
    case dropped
}

public struct TrackedShow: Codable, Identifiable, Sendable, Equatable {
    public var targetID: String
    public var trackedAt: Date
    public var status: TrackedShowStatus

    public var id: String { targetID }

    public init(targetID: String, trackedAt: Date = Date(), status: TrackedShowStatus = .planToWatch) {
        self.targetID = targetID
        self.trackedAt = trackedAt
        self.status = status
    }
}

public enum PlaybillListSystemKind: String, Codable, Sendable {
    case tracking
    case watchlist
}

public struct PlaybillList: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var systemKind: PlaybillListSystemKind?
    public var createdAt: Date
    public var updatedAt: Date

    public var isSystem: Bool { systemKind != nil }

    public init(
        id: UUID = UUID(),
        name: String,
        systemKind: PlaybillListSystemKind? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.systemKind = systemKind
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct PlaybillListItem: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var listID: UUID
    public var targetID: String
    public var addedAt: Date

    public init(id: UUID = UUID(), listID: UUID, targetID: String, addedAt: Date = Date()) {
        self.id = id
        self.listID = listID
        self.targetID = targetID
        self.addedAt = addedAt
    }
}

public struct PlaybillListEntry: Identifiable, Sendable {
    public var id: String { item.targetID }
    public let item: PlaybillListItem
    public let entry: CatalogEntry

    public init(item: PlaybillListItem, entry: CatalogEntry) {
        self.item = item
        self.entry = entry
    }
}

// MARK: - Timeline

public enum PlaybillTimelineSectionKind: String, Sendable {
    case catchUp
    case upNext
    case continueWatching
    case history
}

public struct PlaybillTimelineSection: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let kind: PlaybillTimelineSectionKind
    public let items: [PlaybillTimelineRow]

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        kind: PlaybillTimelineSectionKind,
        items: [PlaybillTimelineRow]
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
        self.items = items
    }
}

public struct PlaybillTimelineRow: Identifiable, Sendable {
    public let id: String
    public let entry: CatalogEntry
    public let showEntry: CatalogEntry?
    public let subtitle: String
    public let badge: String?
    public let date: Date?
    public let progress: TitlePlaybackProgress?
    public let missedCount: Int?
    public let activityID: UUID?

    public init(
        id: String? = nil,
        entry: CatalogEntry,
        showEntry: CatalogEntry? = nil,
        subtitle: String,
        badge: String? = nil,
        date: Date? = nil,
        progress: TitlePlaybackProgress? = nil,
        missedCount: Int? = nil,
        activityID: UUID? = nil
    ) {
        self.id = id ?? entry.id
        self.entry = entry
        self.showEntry = showEntry
        self.subtitle = subtitle
        self.badge = badge
        self.date = date
        self.progress = progress
        self.missedCount = missedCount
        self.activityID = activityID
    }
}

public struct PlaybillShowProgressSummary: Sendable {
    public let show: CatalogEntry
    public let watchedEpisodeCount: Int
    public let nextEpisode: CatalogEntry?
    public let nextEpisodeAirDate: Date?
    public let missedAiredCount: Int

    public init(
        show: CatalogEntry,
        watchedEpisodeCount: Int,
        nextEpisode: CatalogEntry?,
        nextEpisodeAirDate: Date? = nil,
        missedAiredCount: Int
    ) {
        self.show = show
        self.watchedEpisodeCount = watchedEpisodeCount
        self.nextEpisode = nextEpisode
        self.nextEpisodeAirDate = nextEpisodeAirDate
        self.missedAiredCount = missedAiredCount
    }
}

public struct PlaybillEpisodeRef: Sendable, Equatable, Identifiable {
    public let season: Int
    public let episode: Int
    public let episodeID: String

    public var id: String { episodeID }

    public init(season: Int, episode: Int, episodeID: String) {
        self.season = season
        self.episode = episode
        self.episodeID = episodeID
    }
}

// MARK: - Show feed (per-series timeline)

public struct PlaybillFeedEpisode: Identifiable, Sendable, Equatable {
    public let entry: CatalogEntry
    public let watchedAt: Date

    public var id: String { entry.id }

    public init(entry: CatalogEntry, watchedAt: Date) {
        self.entry = entry
        self.watchedAt = watchedAt
    }
}

public struct PlaybillShowFeed: Identifiable, Sendable, Equatable {
    public let id: String
    public let show: CatalogEntry
    /// Most recently watched first (scroll up through the reel).
    public let recentWatched: [PlaybillFeedEpisode]
    public let nextEpisode: CatalogEntry?
    public let missedCount: Int
    public let hasEpisodeMetadata: Bool

    public init(
        id: String? = nil,
        show: CatalogEntry,
        recentWatched: [PlaybillFeedEpisode],
        nextEpisode: CatalogEntry?,
        missedCount: Int,
        hasEpisodeMetadata: Bool = true
    ) {
        self.id = id ?? show.id
        self.show = show
        self.recentWatched = recentWatched
        self.nextEpisode = nextEpisode
        self.missedCount = missedCount
        self.hasEpisodeMetadata = hasEpisodeMetadata
    }
}
