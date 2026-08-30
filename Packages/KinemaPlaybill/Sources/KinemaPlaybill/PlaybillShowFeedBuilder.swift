import Foundation

@MainActor
public enum PlaybillShowFeedBuilder {
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
        let watched = PlaybillShowProgress.watchedEpisodeIDs(for: showTargetID)
        return PlaybillShowFeed(
            show: show,
            recentWatched: recentWatchedEpisodes(for: show.id, limit: recentLimit),
            nextEpisode: PlaybillShowProgress.peekNextEpisode(for: showTargetID, watched: watched),
            missedCount: PlaybillShowProgress.peekMissedAiredCount(for: showTargetID, watched: watched),
            hasEpisodeMetadata: PlaybillShowProgress.hasCompleteEpisodeMetadata(for: show.id)
        )
    }

    public static func buildLightweight(recentLimit: Int = 10) -> [PlaybillShowFeed] {
        PlaybillStore.trackedShows().compactMap { tracked in
            guard tracked.status == .watching || tracked.status == .planToWatch else { return nil }
            return syncFeed(for: tracked.targetID, recentLimit: recentLimit)
        }
    }

    private static func recentWatchedEpisodes(for showTargetID: String, limit: Int) -> [PlaybillFeedEpisode] {
        let db = PlaybillStore.rawDatabase()
        let activities = db.activities
            .filter { $0.completion == .full }
            .sorted { $0.watchedAt > $1.watchedAt }

        var results: [PlaybillFeedEpisode] = []
        for activity in activities {
            guard let entry = db.catalog[activity.targetID],
                  entry.kind == .episode,
                  entry.parentShowID == showTargetID else { continue }
            results.append(PlaybillFeedEpisode(entry: entry, watchedAt: activity.watchedAt))
            if results.count >= limit { break }
        }
        return results
    }
}
