import Foundation
import KinemaMedia

@MainActor
public enum PlaybillShowFeedBuilder {
    private static let cachedRecentLimit = 50
    private static var recentWatchedEpisodesByShowCache: [String: [PlaybillFeedEpisode]]?

    public static func invalidateRecentWatchedEpisodeCache() {
        recentWatchedEpisodesByShowCache = nil
    }

    public static func build(recentLimit: Int = 10, reindexLibrary: Bool = false) async -> [PlaybillShowFeed] {
        if reindexLibrary {
            PlaybillStore.reindexTrackedShowsLibraryMedia()
        }

        var feeds: [PlaybillShowFeed] = []
        for tracked in PlaybillStore.trackedShows() {
            guard tracked.status == .watching || tracked.status == .planToWatch else { continue }
            guard let show = PlaybillStore.entry(for: tracked.targetID), show.kind == .tvShow else { continue }
            // Prefer cache-only first; warm only when this show has no season cache yet.
            if let cached = syncFeed(for: show.id, recentLimit: recentLimit),
               cached.nextEpisode != nil || PlaybillShowProgress.hasWarmCache(for: show.id) {
                feeds.append(cached)
                continue
            }
            if let feed = await feed(for: show.id, recentLimit: recentLimit) {
                feeds.append(feed)
            }
        }
        return feeds
    }

    public static func feed(for showTargetID: String, recentLimit: Int = 10) async -> PlaybillShowFeed? {
        guard let show = PlaybillStore.entry(for: showTargetID), show.kind == .tvShow else { return nil }

        let recentWatched = recentWatchedEpisodes(for: show.id, limit: recentLimit)
        await PlaybillShowProgress.warmCache(for: show.id)
        let summary = await PlaybillShowProgress.progressSummary(for: show.id)

        return PlaybillShowFeed(
            show: show,
            recentWatched: recentWatched,
            nextEpisode: summary?.nextEpisode,
            missedCount: summary?.missedAiredCount ?? 0,
            hasEpisodeMetadata: PlaybillShowProgress.hasCompleteEpisodeMetadata(for: show.id)
        )
    }

    /// Fast in-memory rebuild — no TMDB or full progress scan.
    public static func syncFeed(for showTargetID: String, recentLimit: Int = 10) -> PlaybillShowFeed? {
        guard let show = PlaybillStore.entry(for: showTargetID), show.kind == .tvShow else { return nil }
        let recent = recentWatchedEpisodes(for: show.id, limit: recentLimit)
        // Avoid rebuilding the full watched index when episode metadata is cold.
        let watched: Set<String>
        if PlaybillShowProgress.hasWarmCache(for: showTargetID) {
            watched = PlaybillShowProgress.watchedEpisodeIDs(for: showTargetID)
        } else {
            watched = Set(recent.map(\.entry.id))
        }
        return PlaybillShowFeed(
            show: show,
            recentWatched: recent,
            nextEpisode: PlaybillShowProgress.peekNextEpisode(for: showTargetID, watched: watched),
            missedCount: PlaybillShowProgress.peekMissedAiredCount(for: showTargetID, watched: watched),
            hasEpisodeMetadata: PlaybillShowProgress.hasCompleteEpisodeMetadata(for: show.id)
        )
    }

    public static func buildLightweight(recentLimit: Int = 10) -> [PlaybillShowFeed] {
        let tracked = PlaybillStore.trackedShows()
        guard !tracked.isEmpty else { return [] }
        return tracked.compactMap { tracked in
            guard tracked.status == .watching || tracked.status == .planToWatch else { return nil }
            return syncFeed(for: tracked.targetID, recentLimit: recentLimit)
        }
    }

    private static func recentWatchedEpisodes(for showTargetID: String, limit: Int) -> [PlaybillFeedEpisode] {
        Array(recentWatchedEpisodesByShow()[showTargetID, default: []].prefix(limit))
    }

    private static func recentWatchedEpisodesByShow() -> [String: [PlaybillFeedEpisode]] {
        if let recentWatchedEpisodesByShowCache {
            return recentWatchedEpisodesByShowCache
        }

        let db = PlaybillStore.rawDatabase()
        let shows = db.catalog.values.filter { $0.kind == .tvShow }
        var showIDsByTMDBID: [Int: Set<String>] = [:]
        var showIDsByTitleKey: [String: Set<String>] = [:]
        for show in shows {
            showIDsByTMDBID[show.tmdbID, default: []].insert(show.id)
            showIDsByTitleKey[MediaSeriesOrganizer.showKey(forTitle: show.title), default: []].insert(show.id)
        }

        let activities = db.activities
            .filter { $0.completion == .full }
            .sorted { $0.watchedAt > $1.watchedAt }

        var grouped: [String: [PlaybillFeedEpisode]] = [:]
        for activity in activities {
            guard let entry = db.catalog[activity.targetID], entry.kind == .episode else { continue }
            var showIDs = Set<String>()
            if let parentShowID = entry.parentShowID,
               db.catalog[parentShowID]?.kind == .tvShow {
                showIDs.insert(parentShowID)
            }
            for showID in showIDsByTMDBID[entry.tmdbID, default: []] {
                showIDs.insert(showID)
            }
            if showIDs.isEmpty {
                let titleKey = MediaSeriesOrganizer.showKey(forTitle: entry.title)
                for showID in showIDsByTitleKey[titleKey, default: []] {
                    showIDs.insert(showID)
                }
            }
            for showID in showIDs where grouped[showID, default: []].count < cachedRecentLimit {
                grouped[showID, default: []].append(PlaybillFeedEpisode(entry: entry, watchedAt: activity.watchedAt))
            }
        }

        recentWatchedEpisodesByShowCache = grouped
        return grouped
    }
}
