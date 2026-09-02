import Foundation
import KinemaMedia

@MainActor
public enum PlaybillShowProgress {
    private static var seasonCache: [Int: [TMDBSeasonSummary]] = [:]
    private static var episodeCache: [String: [TMDBEpisodeSummary]] = [:]
    private static var watchedEpisodeIDsByShowCache: [String: Set<String>]?

    public static func invalidateWatchedEpisodeCache() {
        watchedEpisodeIDsByShowCache = nil
    }

    public static func invalidateCachedMetadata(showID: Int) {
        seasonCache.removeValue(forKey: showID)
        let prefix = "\(showID):"
        episodeCache = episodeCache.filter { !$0.key.hasPrefix(prefix) }
    }

    @discardableResult
    public static func pruneUntrustworthySnapshots(in database: inout PlaybillDatabase) -> Int {
        var removed = 0
        for key in Array(database.showMetadataSnapshots.keys) {
            guard let snapshot = database.showMetadataSnapshots[key] else { continue }
            if metadataSnapshotIsTrustworthy(showID: snapshot.tmdbShowID, snapshot: snapshot) { continue }
            database.showMetadataSnapshots.removeValue(forKey: key)
            invalidateCachedMetadata(showID: snapshot.tmdbShowID)
            removed += 1
        }
        return removed
    }

    public static func watchedEpisodeIDs(for showTargetID: String) -> Set<String> {
        guard let show = PlaybillStore.entry(for: showTargetID), show.kind == .tvShow else { return [] }
        hydrateCache(showID: show.tmdbID)
        // Watch history is a user fact. Never discard it because TMDB omitted an
        // air date or reported an incorrect last-aired boundary.
        return watchedEpisodeIDsByShow()[showTargetID] ?? []
    }

    public static func episodeAvailability(
        for showTargetID: String,
        season: Int,
        episode: Int,
        airDate: Date? = nil,
        relativeTo date: Date = Date()
    ) -> PlaybillEpisodeAvailability {
        guard let show = PlaybillStore.entry(for: showTargetID), show.kind == .tvShow else { return .unknown }
        hydrateCache(showID: show.tmdbID)
        return episodeAvailability(
            for: show,
            season: season,
            episode: episode,
            airDate: airDate,
            relativeTo: date
        )
    }

    public static func episodeAvailability(
        for episode: CatalogEntry,
        in showTargetID: String,
        relativeTo date: Date = Date()
    ) -> PlaybillEpisodeAvailability {
        guard let season = episode.seasonNumber, let number = episode.episodeNumber else { return .unknown }
        return episodeAvailability(
            for: showTargetID,
            season: season,
            episode: number,
            airDate: episode.episodeAirDate,
            relativeTo: date
        )
    }

    /// Preload season/episode lists so stamping feels instant.
    public static func warmCache(for showTargetID: String) async {
        guard let show = PlaybillStore.entry(for: showTargetID), show.kind == .tvShow else { return }
        hydrateCache(showID: show.tmdbID)
        _ = await ensureSeasonsLoaded(showID: show.tmdbID, allowNetwork: true, persist: false)
        guard let seasons = seasonCache[show.tmdbID] else { return }
        for season in seasons where season.seasonNumber > 0 {
            _ = await ensureEpisodesLoaded(
                showID: show.tmdbID,
                season: season.seasonNumber,
                allowNetwork: true,
                persist: false
            )
            await Task.yield()
        }
        persistCache(showID: show.tmdbID)
    }

    public static func hasWarmCache(for showTargetID: String) -> Bool {
        guard let show = PlaybillStore.entry(for: showTargetID), show.kind == .tvShow else { return false }
        hydrateCache(showID: show.tmdbID)
        guard let seasons = seasonCache[show.tmdbID], !seasons.isEmpty else { return false }
        return seasons.contains { season in
            season.seasonNumber > 0
                && episodeCache[episodeCacheKey(showID: show.tmdbID, season: season.seasonNumber)] != nil
        }
    }

    public static func hasCompleteEpisodeMetadata(for showTargetID: String) -> Bool {
        guard let show = PlaybillStore.entry(for: showTargetID), show.kind == .tvShow else { return false }
        return metadataSnapshotIsTrustworthy(showID: show.tmdbID)
    }

    /// Next unwatched episode using cache — no placeholder UI wait.
    public static func nextEpisode(for showTargetID: String) async -> CatalogEntry? {
        await resolveNextEpisode(for: showTargetID, watched: watchedEpisodeIDs(for: showTargetID))
    }

    /// After stamping, derive the next slot immediately when cache is warm.
    public static func nextEpisodeAfterStamping(
        showTargetID: String,
        stampedEpisodeID: String
    ) async -> CatalogEntry? {
        var watched = watchedEpisodeIDs(for: showTargetID)
        watched.insert(stampedEpisodeID)
        return await resolveNextEpisode(for: showTargetID, watched: watched)
    }

    /// Synchronous peek when seasons/episodes are already cached.
    public static func peekNextEpisode(for showTargetID: String, watched: Set<String>? = nil) -> CatalogEntry? {
        guard let show = PlaybillStore.entry(for: showTargetID), show.kind == .tvShow else { return nil }
        hydrateCache(showID: show.tmdbID)
        let watchedIDs = watched ?? watchedEpisodeIDs(for: showTargetID)
        guard let seasons = seasonCache[show.tmdbID] else { return nil }

        for season in seasons where season.seasonNumber > 0 {
            let key = episodeCacheKey(showID: show.tmdbID, season: season.seasonNumber)
            guard let episodes = episodeCache[key] else { return nil }
            for episode in episodes {
                let episodeID = CatalogEntry.episodeID(
                    showTmdbID: show.tmdbID,
                    season: season.seasonNumber,
                    episode: episode.episodeNumber
                )
                if watchedIDs.contains(episodeID) { continue }
                if showHasEnded(show),
                   !episodeAvailability(
                       for: show,
                       season: season.seasonNumber,
                       episode: episode.episodeNumber,
                       airDate: episode.airDate
                   ).canMarkWatched {
                    continue
                }
                if let entry = PlaybillStore.entry(for: episodeID) {
                    return entry
                }
                return skeletonEpisode(
                    show: show,
                    season: season.seasonNumber,
                    episode: episode
                )
            }
        }
        return nil
    }

    public static func progressSummary(
        for showTargetID: String,
        allowNetwork: Bool = true
    ) async -> PlaybillShowProgressSummary? {
        guard let show = PlaybillStore.entry(for: showTargetID), show.kind == .tvShow else { return nil }
        guard PlaybillPreferencesStore.isConfigured else { return nil }

        let watched = watchedEpisodeIDs(for: showTargetID)
        let today = Calendar.current.startOfDay(for: Date())
        var missedAired = 0
        var nextUnwatchedAirDate: Date?

        _ = await ensureSeasonsLoaded(showID: show.tmdbID, allowNetwork: allowNetwork, persist: false)
        guard let seasons = seasonCache[show.tmdbID], !seasons.isEmpty else {
            return PlaybillShowProgressSummary(
                show: show,
                watchedEpisodeCount: watched.count,
                nextEpisode: nil,
                missedAiredCount: conservativeMissedAiredCount(
                    show: show,
                    watchedCount: watched.count,
                    metadataComplete: false
                )
            )
        }

        var metadataComplete = true
        for season in seasons where season.seasonNumber > 0 {
            guard let episodes = await ensureEpisodesLoaded(
                showID: show.tmdbID,
                season: season.seasonNumber,
                allowNetwork: allowNetwork,
                persist: false
            ) else {
                metadataComplete = false
                continue
            }
            for episode in episodes {
                let episodeID = CatalogEntry.episodeID(
                    showTmdbID: show.tmdbID,
                    season: season.seasonNumber,
                    episode: episode.episodeNumber
                )
                if watched.contains(episodeID) { continue }
                if nextUnwatchedAirDate == nil {
                    nextUnwatchedAirDate = episode.airDate
                }
                if episodeAvailability(
                    for: show,
                    season: season.seasonNumber,
                    episode: episode.episodeNumber,
                    airDate: episode.airDate,
                    relativeTo: today
                ).canMarkWatched {
                    missedAired += 1
                }
            }
        }

        if !metadataComplete {
            missedAired = max(
                missedAired,
                conservativeMissedAiredCount(
                    show: show,
                    watchedCount: watched.count,
                    metadataComplete: false
                )
            )
        }

        let next = allowNetwork
            ? await resolveNextEpisode(for: showTargetID, watched: watched)
            : peekNextEpisode(for: showTargetID, watched: watched)

        if allowNetwork {
            // A detail refresh must survive relaunch; otherwise the lightweight
            // Playbill card falls back to the imported watched subset again.
            persistCache(showID: show.tmdbID)
        }

        return PlaybillShowProgressSummary(
            show: show,
            watchedEpisodeCount: watched.count,
            nextEpisode: next,
            nextEpisodeAirDate: nextUnwatchedAirDate,
            missedAiredCount: missedAired
        )
    }

    /// Derive lifecycle from facts: watched progress plus TMDB production/release data.
    /// `TrackedShowStatus` is storage for the derived result, never a user decision.
    public static func derivedTrackingStatus(
        for showTargetID: String,
        summary: PlaybillShowProgressSummary
    ) -> TrackedShowStatus {
        if summary.watchedEpisodeCount == 0 { return .planToWatch }
        if summary.missedAiredCount > 0 { return .watching }

        let show = summary.show
        let hasEnded = PlaybillStore.seriesIsEffectivelyFinished(
            showTargetID: showTargetID,
            watchedCount: summary.watchedEpisodeCount
        )
        if hasEnded {
            if shouldMarkCompleted(
                show: show,
                watchedCount: summary.watchedEpisodeCount,
                metadataComplete: hasCompleteEpisodeMetadata(for: showTargetID)
            ) {
                return .completed
            }
            return .watching
        }
        return .waiting
    }

    @discardableResult
    public static func reconcileTrackingState(
        for showTargetID: String,
        allowNetwork: Bool = false
    ) async -> TrackedShowStatus? {
        guard let tracked = PlaybillStore.trackedShow(for: showTargetID),
              var show = PlaybillStore.entry(for: showTargetID),
              show.kind == .tvShow else { return nil }

        let watchedCount = watchedEpisodeIDs(for: showTargetID).count

        // Fast path: false "Completed" after Trakt import — demote without TMDB.
        if tracked.status == .completed,
           (!PlaybillStore.seriesIsEffectivelyFinished(
               showTargetID: showTargetID,
               watchedCount: watchedCount
           ) || watchedCount < PlaybillStore.displayEpisodeTotal(for: show)) {
            PlaybillStore.updateTrackedShowStatus(targetID: showTargetID, status: .watching, notify: false)
            return .watching
        }

        if allowNetwork {
            let metadataIsStale = tracked.status == .waiting
                || show.seriesStatus == nil
                || show.lastAiredSeasonNumber == nil
                || Date().timeIntervalSince(show.cachedAt) > 3_600
            if metadataIsStale, let refreshed = try? await TMDBClient.fetchTVShow(id: show.tmdbID) {
                show = PlaybillStore.upsertCatalog(refreshed)
                await refreshCacheFromNetwork(showID: show.tmdbID)
            } else if !hasCompleteEpisodeMetadata(for: showTargetID) {
                await warmCache(for: showTargetID)
            }
        }

        guard let summary = await progressSummary(for: showTargetID, allowNetwork: allowNetwork) else {
            return tracked.status
        }

        let derived = derivedTrackingStatus(for: showTargetID, summary: summary)
        PlaybillStore.updateTrackedShowStatus(targetID: showTargetID, status: derived, notify: allowNetwork)
        return derived
    }

    public static func seasonRows(
        for showTargetID: String
    ) async -> [(season: TMDBSeasonSummary, episodes: [TMDBEpisodeSummary])] {
        guard let show = PlaybillStore.entry(for: showTargetID), show.kind == .tvShow else { return [] }
        guard PlaybillPreferencesStore.isConfigured else { return [] }

        guard await ensureSeasonsLoaded(showID: show.tmdbID, allowNetwork: true, persist: false),
              let seasons = seasonCache[show.tmdbID] else { return [] }

        var rows: [(TMDBSeasonSummary, [TMDBEpisodeSummary])] = []
        let watched = watchedEpisodeIDs(for: showTargetID)
        for season in seasons where season.seasonNumber > 0 {
            if let episodes = await ensureEpisodesLoaded(
                showID: show.tmdbID,
                season: season.seasonNumber,
                allowNetwork: true,
                persist: false
            ) {
                let visibleEpisodes: [TMDBEpisodeSummary]
                if showHasEnded(show) {
                    visibleEpisodes = episodes.filter { episode in
                        let episodeID = CatalogEntry.episodeID(
                            showTmdbID: show.tmdbID,
                            season: season.seasonNumber,
                            episode: episode.episodeNumber
                        )
                        return watched.contains(episodeID)
                            || episodeAvailability(
                                for: show,
                                season: season.seasonNumber,
                                episode: episode.episodeNumber,
                                airDate: episode.airDate
                            ).canMarkWatched
                    }
                } else {
                    visibleEpisodes = episodes
                }
                if !visibleEpisodes.isEmpty {
                    rows.append((season, visibleEpisodes))
                }
            }
        }
        persistCache(showID: show.tmdbID)
        return rows
    }

    /// Unwatched episodes airing before the given slot, in broadcast order.
    public static func priorUnwatchedEpisodes(
        for showTargetID: String,
        upToSeason season: Int,
        upToEpisode episode: Int,
        watched watchedIDs: Set<String>? = nil
    ) -> [PlaybillEpisodeRef] {
        guard let show = PlaybillStore.entry(for: showTargetID), show.kind == .tvShow else { return [] }
        hydrateCache(showID: show.tmdbID)
        let watchedSet = watchedIDs ?? watchedEpisodeIDs(for: showTargetID)
        guard let seasons = seasonCache[show.tmdbID] else { return [] }

        var results: [PlaybillEpisodeRef] = []
        for seasonSummary in seasons where seasonSummary.seasonNumber > 0 {
            let seasonNumber = seasonSummary.seasonNumber
            let cacheKey = episodeCacheKey(showID: show.tmdbID, season: seasonNumber)
            guard let episodes = episodeCache[cacheKey] else { return results }

            for episodeSummary in episodes {
                let episodeNumber = episodeSummary.episodeNumber
                if seasonNumber > season || (seasonNumber == season && episodeNumber >= episode) {
                    return results
                }
                let episodeID = CatalogEntry.episodeID(
                    showTmdbID: show.tmdbID,
                    season: seasonNumber,
                    episode: episodeNumber
                )
                if !watchedSet.contains(episodeID),
                   episodeAvailability(
                       for: show,
                       season: seasonNumber,
                       episode: episodeNumber,
                       airDate: episodeSummary.airDate
                   ).canMarkWatched {
                    results.append(PlaybillEpisodeRef(
                        season: seasonNumber,
                        episode: episodeNumber,
                        episodeID: episodeID
                    ))
                }
            }
        }
        return results
    }

    /// Mark one episode — optionally including all earlier unwatched slots.
    public static func markEpisodeWatched(
        showTargetID: String,
        season: Int,
        episode: Int,
        includePriorUnwatched: Bool,
        watchedAt: Date = Date()
    ) -> Bool {
        guard let show = PlaybillStore.entry(for: showTargetID), show.kind == .tvShow else { return false }
        guard episodeAvailability(
            for: show,
            season: season,
            episode: episode,
            relativeTo: watchedAt
        ).canMarkWatched else { return false }

        var refs = priorUnwatchedEpisodes(
            for: showTargetID,
            upToSeason: season,
            upToEpisode: episode
        )
        if !includePriorUnwatched {
            refs = []
        }

        let targetID = CatalogEntry.episodeID(showTmdbID: show.tmdbID, season: season, episode: episode)
        if !refs.contains(where: { $0.episodeID == targetID }) {
            refs.append(PlaybillEpisodeRef(season: season, episode: episode, episodeID: targetID))
        }

        var targetIDs: [String] = []
        for ref in refs {
            let entry = ensureEpisodeEntrySync(show: show, season: ref.season, episode: ref.episode)
            targetIDs.append(entry.id)
        }

        return PlaybillStore.logWatchBatch(targetIDs: targetIDs, watchedAt: watchedAt, source: .manual) > 0
    }

    /// Cached-only missed-episode count for lightweight UI refresh.
    public static func peekMissedAiredCount(
        for showTargetID: String,
        watched watchedIDs: Set<String>? = nil
    ) -> Int {
        guard let show = PlaybillStore.entry(for: showTargetID), show.kind == .tvShow else { return 0 }
        hydrateCache(showID: show.tmdbID)
        let watchedSet = watchedIDs ?? watchedEpisodeIDs(for: showTargetID)
        guard let seasons = seasonCache[show.tmdbID] else { return 0 }

        let today = Calendar.current.startOfDay(for: Date())
        var missedAired = 0
        for season in seasons where season.seasonNumber > 0 {
            let cacheKey = episodeCacheKey(showID: show.tmdbID, season: season.seasonNumber)
            guard let episodes = episodeCache[cacheKey] else { return missedAired }
            for episode in episodes {
                let episodeID = CatalogEntry.episodeID(
                    showTmdbID: show.tmdbID,
                    season: season.seasonNumber,
                    episode: episode.episodeNumber
                )
                if watchedSet.contains(episodeID) { continue }
                if let airDate = episode.airDate, airDate <= today {
                    missedAired += 1
                } else if episode.airDate == nil,
                          episodeAvailability(
                              for: show,
                              season: season.seasonNumber,
                              episode: episode.episodeNumber
                          ) == .released {
                    missedAired += 1
                }
            }
        }
        return missedAired
    }

    // MARK: - Private

    private static func watchedEpisodeIDsByShow() -> [String: Set<String>] {
        if let watchedEpisodeIDsByShowCache {
            return watchedEpisodeIDsByShowCache
        }

        let db = PlaybillStore.rawDatabase()
        let shows = db.catalog.values.filter { $0.kind == .tvShow }
        var showIDsByTMDBID: [Int: Set<String>] = [:]
        var showIDsByTitleKey: [String: Set<String>] = [:]
        for show in shows {
            showIDsByTMDBID[show.tmdbID, default: []].insert(show.id)
            showIDsByTitleKey[MediaSeriesOrganizer.showKey(forTitle: show.title), default: []].insert(show.id)
        }

        var grouped: [String: Set<String>] = [:]
        for activity in db.activities where activity.completion == .full {
            guard let episode = db.catalog[activity.targetID], episode.kind == .episode else { continue }
            var showIDs = Set<String>()
            if let parentShowID = episode.parentShowID,
               db.catalog[parentShowID]?.kind == .tvShow {
                showIDs.insert(parentShowID)
            }
            for showID in showIDsByTMDBID[episode.tmdbID, default: []] {
                showIDs.insert(showID)
            }
            if showIDs.isEmpty {
                let episodeTitleKey = MediaSeriesOrganizer.showKey(forTitle: episode.title)
                for showID in showIDsByTitleKey[episodeTitleKey, default: []] {
                    showIDs.insert(showID)
                }
            }
            for showID in showIDs {
                let canonicalID: String
                if let show = db.catalog[showID],
                   let season = episode.seasonNumber,
                   let number = episode.episodeNumber {
                    canonicalID = CatalogEntry.episodeID(
                        showTmdbID: show.tmdbID,
                        season: season,
                        episode: number
                    )
                } else {
                    canonicalID = activity.targetID
                }
                grouped[showID, default: []].insert(canonicalID)
            }
        }

        watchedEpisodeIDsByShowCache = grouped
        return grouped
    }

    private static func resolveNextEpisode(for showTargetID: String, watched: Set<String>) async -> CatalogEntry? {
        if let peeked = peekNextEpisode(for: showTargetID, watched: watched),
           PlaybillStore.entry(for: peeked.id) != nil {
            return peeked
        }

        guard let show = PlaybillStore.entry(for: showTargetID), show.kind == .tvShow else { return nil }
        guard await ensureSeasonsLoaded(showID: show.tmdbID),
              let seasons = seasonCache[show.tmdbID] else { return nil }

        for season in seasons where season.seasonNumber > 0 {
            guard let episodes = await ensureEpisodesLoaded(showID: show.tmdbID, season: season.seasonNumber) else {
                continue
            }
            for episode in episodes {
                let episodeID = CatalogEntry.episodeID(
                    showTmdbID: show.tmdbID,
                    season: season.seasonNumber,
                    episode: episode.episodeNumber
                )
                if watched.contains(episodeID) { continue }
                if showHasEnded(show),
                   !episodeAvailability(
                       for: show,
                       season: season.seasonNumber,
                       episode: episode.episodeNumber,
                       airDate: episode.airDate
                   ).canMarkWatched {
                    continue
                }

                if let cached = PlaybillStore.entry(for: episodeID) {
                    return cached
                }
                if let fetched = try? await TMDBClient.fetchEpisode(
                    showID: show.tmdbID,
                    season: season.seasonNumber,
                    episode: episode.episodeNumber
                ) {
                    _ = PlaybillStore.upsertCatalog(fetched)
                    return fetched
                }
                return skeletonEpisode(show: show, season: season.seasonNumber, episode: episode)
            }
        }
        return nil
    }

    @discardableResult
    private static func ensureSeasonsLoaded(
        showID: Int,
        allowNetwork: Bool = true,
        persist: Bool = true
    ) async -> Bool {
        hydrateCache(showID: showID)
        if metadataSnapshotIsTrustworthy(showID: showID), seasonCache[showID] != nil {
            return true
        }
        if seasonCache[showID] != nil, !allowNetwork {
            return true
        }

        guard allowNetwork, PlaybillPreferencesStore.isConfigured else {
            return seasonCache[showID] != nil
        }
        if let seasons = try? await TMDBClient.fetchSeasonSummaries(showID: showID) {
            seasonCache[showID] = seasons
            if persist { persistCache(showID: showID) }
            return true
        }
        return seasonCache[showID] != nil
    }

    @discardableResult
    private static func ensureEpisodesLoaded(
        showID: Int,
        season: Int,
        allowNetwork: Bool = true,
        persist: Bool = true
    ) async -> [TMDBEpisodeSummary]? {
        hydrateCache(showID: showID)
        let key = episodeCacheKey(showID: showID, season: season)
        let showTargetID = CatalogEntry.showID(showID)
        if let snapshot = PlaybillStore.showMetadataSnapshot(for: showTargetID),
           let seasonSnapshot = snapshot.seasons.first(where: { $0.seasonNumber == season }),
           seasonSnapshot.episodeCount > 0,
           seasonSnapshot.episodes.count >= seasonSnapshot.episodeCount {
            if episodeCache[key] == nil {
                episodeCache[key] = seasonSnapshot.episodes.map {
                    TMDBEpisodeSummary(
                        episodeNumber: $0.episodeNumber,
                        name: $0.name,
                        airDate: $0.airDate,
                        runtimeMinutes: $0.runtimeMinutes,
                        stillPath: $0.stillPath
                    )
                }
            }
            return episodeCache[key]
        }

        if let cached = episodeCache[key],
           let seasonSummary = seasonCache[showID]?.first(where: { $0.seasonNumber == season }),
           seasonSummary.episodeCount > 0,
           cached.count >= seasonSummary.episodeCount {
            return cached
        }

        // Incomplete cache is fine when network is disallowed (list open path).
        if !allowNetwork {
            return episodeCache[key]
        }

        guard PlaybillPreferencesStore.isConfigured else { return episodeCache[key] }
        if let episodes = try? await TMDBClient.fetchSeasonEpisodes(showID: showID, season: season) {
            episodeCache[key] = episodes
            if persist { persistCache(showID: showID) }
            return episodes
        }
        return episodeCache[key]
    }

    private static func episodeCacheKey(showID: Int, season: Int) -> String {
        "\(showID):\(season)"
    }

    private static func episodeSlot(from targetID: String) -> (season: Int, episode: Int)? {
        guard let seasonMarker = targetID.range(of: ":s", options: .backwards),
              let episodeMarker = targetID.range(of: "e", range: seasonMarker.upperBound..<targetID.endIndex),
              let season = Int(targetID[seasonMarker.upperBound..<episodeMarker.lowerBound]),
              let episode = Int(targetID[episodeMarker.upperBound...]) else {
            return nil
        }
        return (season, episode)
    }

    private static func episodeAvailability(
        for show: CatalogEntry,
        season: Int,
        episode: Int,
        airDate suppliedAirDate: Date? = nil,
        relativeTo date: Date = Date()
    ) -> PlaybillEpisodeAvailability {
        let episodeID = CatalogEntry.episodeID(
            showTmdbID: show.tmdbID,
            season: season,
            episode: episode
        )
        if watchedEpisodeIDsByShow()[show.id]?.contains(episodeID) == true {
            return .released
        }

        let cachedAirDate = episodeCache[episodeCacheKey(showID: show.tmdbID, season: season)]?
            .first(where: { $0.episodeNumber == episode })?
            .airDate
        if let airDate = suppliedAirDate ?? cachedAirDate {
            let calendar = Calendar.current
            return calendar.startOfDay(for: airDate) <= calendar.startOfDay(for: date)
                ? .released
                : .upcoming(airDate)
        }

        if let lastSeason = show.lastAiredSeasonNumber,
           let lastEpisode = show.lastAiredEpisodeNumber {
            if season < lastSeason || (season == lastSeason && episode <= lastEpisode) {
                return .released
            }
            return .unscheduled
        }
        return .unknown
    }

    /// Refresh opportunistically while retaining any older per-season episode map
    /// whose individual request fails. Freshness must never destroy offline coverage.
    private static func refreshCacheFromNetwork(showID: Int) async {
        hydrateCache(showID: showID)
        guard let refreshedSeasons = try? await TMDBClient.fetchSeasonSummaries(showID: showID) else { return }
        seasonCache[showID] = refreshedSeasons
        for season in refreshedSeasons where season.seasonNumber > 0 {
            if let episodes = try? await TMDBClient.fetchSeasonEpisodes(showID: showID, season: season.seasonNumber) {
                episodeCache[episodeCacheKey(showID: showID, season: season.seasonNumber)] = episodes
            }
        }
        persistCache(showID: showID)
    }

    private static func hydrateCache(showID: Int) {
        guard seasonCache[showID] == nil else { return }
        if let snapshot = PlaybillStore.showMetadataSnapshot(for: CatalogEntry.showID(showID)),
           metadataSnapshotIsTrustworthy(showID: showID, snapshot: snapshot) {
            seasonCache[showID] = snapshot.seasons.map {
                TMDBSeasonSummary(seasonNumber: $0.seasonNumber, episodeCount: $0.episodeCount, name: $0.name)
            }
            for season in snapshot.seasons where !season.episodes.isEmpty {
                episodeCache[episodeCacheKey(showID: showID, season: season.seasonNumber)] = season.episodes.map {
                    TMDBEpisodeSummary(
                        episodeNumber: $0.episodeNumber,
                        name: $0.name,
                        airDate: $0.airDate,
                        runtimeMinutes: $0.runtimeMinutes,
                        stillPath: $0.stillPath
                    )
                }
            }
            return
        }

        // Offline-only fallback: Trakt import stores watched episodes in the catalog,
        // but that must never masquerade as the full series episode map.
        guard !PlaybillPreferencesStore.isConfigured else { return }

        // Migration fallback: older databases already contain catalog episodes even
        // though they predate persistent season snapshots.
        let showTargetID = CatalogEntry.showID(showID)
        let db = PlaybillStore.rawDatabase()
        let show = db.catalog[showTargetID]
        let episodes = db.catalog.values.filter {
            guard $0.kind == .episode,
                  $0.seasonNumber != nil,
                  $0.episodeNumber != nil else {
                return false
            }
            if $0.parentShowID == showTargetID || $0.tmdbID == showID {
                return true
            }
            guard let show else { return false }
            return PlaybillStore.episode($0, belongsTo: show)
        }
        let grouped = Dictionary(grouping: episodes, by: { $0.seasonNumber! })
        guard !grouped.isEmpty else { return }
        seasonCache[showID] = grouped.keys.sorted().map { season in
            let rows = grouped[season, default: []]
            episodeCache[episodeCacheKey(showID: showID, season: season)] = rows.compactMap { entry in
                guard let number = entry.episodeNumber else { return nil }
                return TMDBEpisodeSummary(
                    episodeNumber: number,
                    name: entry.subtitle ?? "Episode \(number)",
                    airDate: nil,
                    runtimeMinutes: entry.runtimeMinutes,
                    stillPath: entry.posterPath ?? entry.backdropPath
                )
            }.sorted { $0.episodeNumber < $1.episodeNumber }
            return TMDBSeasonSummary(
                seasonNumber: season,
                episodeCount: rows.count,
                name: "Season \(season)"
            )
        }
    }

    private static func metadataSnapshotIsTrustworthy(showID: Int, snapshot: PlaybillShowMetadataSnapshot? = nil) -> Bool {
        let showTargetID = CatalogEntry.showID(showID)
        let snapshot = snapshot ?? PlaybillStore.showMetadataSnapshot(for: showTargetID)
        guard let snapshot, snapshot.hasCompleteEpisodeMap else { return false }

        guard let show = PlaybillStore.entry(for: showTargetID),
              let expectedTotal = show.totalEpisodeCount,
              expectedTotal > 0 else {
            return true
        }

        let cachedTotal = snapshot.seasons
            .filter { $0.seasonNumber > 0 }
            .reduce(0) { partial, season in
                partial + max(season.episodeCount, season.episodes.count)
            }
        guard cachedTotal > 0 else { return false }

        // Reject truncated maps (e.g. only the Trakt-imported watched slots).
        return cachedTotal * 10 >= expectedTotal * 8
    }

    private static func persistCache(showID: Int) {
        guard let seasons = seasonCache[showID] else { return }
        let cachedSeasons = seasons.map { season in
            let episodes = episodeCache[episodeCacheKey(showID: showID, season: season.seasonNumber)] ?? []
            return PlaybillCachedSeason(
                seasonNumber: season.seasonNumber,
                episodeCount: season.episodeCount,
                name: season.name,
                episodes: episodes.map {
                    PlaybillCachedEpisode(
                        episodeNumber: $0.episodeNumber,
                        name: $0.name,
                        airDate: $0.airDate,
                        runtimeMinutes: $0.runtimeMinutes,
                        stillPath: $0.stillPath
                    )
                }
            )
        }
        PlaybillStore.saveShowMetadataSnapshot(PlaybillShowMetadataSnapshot(
            showTargetID: CatalogEntry.showID(showID),
            tmdbShowID: showID,
            seasons: cachedSeasons
        ))
    }

    private static func skeletonEpisode(
        show: CatalogEntry,
        season: Int,
        episode: TMDBEpisodeSummary
    ) -> CatalogEntry {
        CatalogEntry(
            id: CatalogEntry.episodeID(showTmdbID: show.tmdbID, season: season, episode: episode.episodeNumber),
            kind: .episode,
            tmdbID: show.tmdbID,
            parentShowID: show.id,
            title: show.title,
            subtitle: episode.name,
            year: nil,
            overview: nil,
            posterPath: episode.stillPath,
            backdropPath: episode.stillPath,
            genres: [],
            runtimeMinutes: episode.runtimeMinutes,
            seasonNumber: season,
            episodeNumber: episode.episodeNumber,
            episodeAirDate: episode.airDate,
            cachedAt: Date()
        )
    }

    private static func ensureEpisodeEntrySync(
        show: CatalogEntry,
        season: Int,
        episode: Int
    ) -> CatalogEntry {
        let episodeID = CatalogEntry.episodeID(showTmdbID: show.tmdbID, season: season, episode: episode)
        if let existing = PlaybillStore.entry(for: episodeID) {
            return existing
        }

        let cacheKey = episodeCacheKey(showID: show.tmdbID, season: season)
        if let episodes = episodeCache[cacheKey],
           let summary = episodes.first(where: { $0.episodeNumber == episode }) {
            let skeleton = skeletonEpisode(show: show, season: season, episode: summary)
            _ = PlaybillStore.upsertCatalog(skeleton)
            return skeleton
        }

        let fallback = CatalogEntry(
            id: episodeID,
            kind: .episode,
            tmdbID: show.tmdbID,
            parentShowID: show.id,
            title: show.title,
            subtitle: "Episode \(episode)",
            year: nil,
            overview: nil,
            posterPath: nil,
            backdropPath: nil,
            genres: [],
            runtimeMinutes: nil,
            seasonNumber: season,
            episodeNumber: episode,
            episodeAirDate: nil,
            cachedAt: Date()
        )
        _ = PlaybillStore.upsertCatalog(fallback)
        return fallback
    }

    private static func ensureEpisodeEntry(
        show: CatalogEntry,
        season: Int,
        episode: Int,
        allowNetworkFetch: Bool = true
    ) async -> CatalogEntry {
        let episodeID = CatalogEntry.episodeID(showTmdbID: show.tmdbID, season: season, episode: episode)
        if let existing = PlaybillStore.entry(for: episodeID) {
            return existing
        }

        let cacheKey = episodeCacheKey(showID: show.tmdbID, season: season)
        if let episodes = episodeCache[cacheKey],
           let summary = episodes.first(where: { $0.episodeNumber == episode }) {
            let skeleton = skeletonEpisode(show: show, season: season, episode: summary)
            _ = PlaybillStore.upsertCatalog(skeleton)
            return skeleton
        }

        if allowNetworkFetch,
           let fetched = try? await TMDBClient.fetchEpisode(
               showID: show.tmdbID,
               season: season,
               episode: episode
           ) {
            _ = PlaybillStore.upsertCatalog(fetched)
            return fetched
        }

        let fallback = CatalogEntry(
            id: episodeID,
            kind: .episode,
            tmdbID: show.tmdbID,
            parentShowID: show.id,
            title: show.title,
            subtitle: "Episode \(episode)",
            year: nil,
            overview: nil,
            posterPath: nil,
            backdropPath: nil,
            genres: [],
            runtimeMinutes: nil,
            seasonNumber: season,
            episodeNumber: episode,
            episodeAirDate: nil,
            cachedAt: Date()
        )
        _ = PlaybillStore.upsertCatalog(fallback)
        return fallback
    }

    private static func showHasEnded(_ show: CatalogEntry) -> Bool {
        let normalized = show.seriesStatus?.lowercased() ?? ""
        return normalized == "ended"
            || normalized == "canceled"
            || (show.seriesInProduction == false && show.nextEpisodeAirDate == nil)
    }

    private static func shouldMarkCompleted(
        show: CatalogEntry,
        watchedCount: Int,
        metadataComplete: Bool
    ) -> Bool {
        guard watchedCount > 0 else { return false }
        if metadataComplete { return true }
        guard let total = show.totalEpisodeCount, total > 0 else { return false }
        return watchedCount >= total
    }

    /// When episode metadata is incomplete, never assume zero missed episodes.
    private static func conservativeMissedAiredCount(
        show: CatalogEntry,
        watchedCount: Int,
        metadataComplete: Bool
    ) -> Int {
        guard watchedCount > 0, !metadataComplete else { return 0 }
        if let total = show.totalEpisodeCount, total > watchedCount {
            return total - watchedCount
        }
        return 1
    }
}
