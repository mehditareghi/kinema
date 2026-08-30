import Foundation

@MainActor
public enum PlaybillShowProgress {
    private static var seasonCache: [Int: [TMDBSeasonSummary]] = [:]
    private static var episodeCache: [String: [TMDBEpisodeSummary]] = [:]

    public static func watchedEpisodeIDs(for showTargetID: String) -> Set<String> {
        let db = PlaybillStore.rawDatabase()
        let watched = db.activities
            .filter { $0.completion == .full }
            .map(\.targetID)
        return Set(watched.filter { targetID in
            guard let entry = db.catalog[targetID], entry.kind == .episode else { return false }
            return entry.parentShowID == showTargetID
        })
    }

    /// Preload season/episode lists so stamping feels instant.
    public static func warmCache(for showTargetID: String) async {
        guard let show = PlaybillStore.entry(for: showTargetID), show.kind == .tvShow else { return }
        hydrateCache(showID: show.tmdbID)
        _ = await ensureSeasonsLoaded(showID: show.tmdbID)
        guard let seasons = seasonCache[show.tmdbID] else { return }
        for season in seasons where season.seasonNumber > 0 {
            _ = await ensureEpisodesLoaded(showID: show.tmdbID, season: season.seasonNumber)
        }

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
        hydrateCache(showID: show.tmdbID)
        guard let seasons = seasonCache[show.tmdbID] else { return false }
        let regularSeasons = seasons.filter { $0.seasonNumber > 0 }
        guard !regularSeasons.isEmpty else { return false }
        return regularSeasons.allSatisfy { season in
            let episodes = episodeCache[episodeCacheKey(showID: show.tmdbID, season: season.seasonNumber)]
            return season.episodeCount == 0 || (episodes?.count ?? 0) >= season.episodeCount
        }
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

    public static func progressSummary(for showTargetID: String) async -> PlaybillShowProgressSummary? {
        guard let show = PlaybillStore.entry(for: showTargetID), show.kind == .tvShow else { return nil }
        guard PlaybillPreferencesStore.isConfigured else { return nil }

        let watched = watchedEpisodeIDs(for: showTargetID)
        let today = Calendar.current.startOfDay(for: Date())
        var missedAired = 0
        var nextUnwatchedAirDate: Date?

        _ = await ensureSeasonsLoaded(showID: show.tmdbID)
        guard let seasons = seasonCache[show.tmdbID] else {
            return PlaybillShowProgressSummary(
                show: show,
                watchedEpisodeCount: watched.count,
                nextEpisode: nil,
                missedAiredCount: 0
            )
        }

        // The detailed episode cache can be partial. Establish a second,
        // cache-independent count from season totals and the last-aired boundary.
        let boundaryAiredCount: Int = {
            guard let lastSeason = show.lastAiredSeasonNumber,
                  let lastEpisode = show.lastAiredEpisodeNumber else { return 0 }
            return seasons.reduce(into: 0) { count, season in
                guard season.seasonNumber > 0 else { return }
                if season.seasonNumber < lastSeason {
                    count += season.episodeCount
                } else if season.seasonNumber == lastSeason {
                    count += min(season.episodeCount, lastEpisode)
                }
            }
        }()

        let watchedAiredCount: Int = {
            guard let lastSeason = show.lastAiredSeasonNumber,
                  let lastEpisode = show.lastAiredEpisodeNumber else { return 0 }
            return watched.reduce(into: 0) { count, targetID in
                guard let entry = PlaybillStore.entry(for: targetID),
                      let season = entry.seasonNumber,
                      let episode = entry.episodeNumber,
                      season > 0 else { return }
                if season < lastSeason || (season == lastSeason && episode <= lastEpisode) {
                    count += 1
                }
            }
        }()

        var hasCompleteEpisodeMap = true
        for season in seasons where season.seasonNumber > 0 {
            guard let episodes = await ensureEpisodesLoaded(showID: show.tmdbID, season: season.seasonNumber) else {
                hasCompleteEpisodeMap = false
                continue
            }
            if season.episodeCount > 0 && episodes.count < season.episodeCount {
                hasCompleteEpisodeMap = false
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
                let releasedByDate = episode.airDate.map { $0 <= today } ?? false
                let releasedByBoundary: Bool = {
                    guard let lastSeason = show.lastAiredSeasonNumber,
                          let lastEpisode = show.lastAiredEpisodeNumber else { return false }
                    return season.seasonNumber < lastSeason
                        || (season.seasonNumber == lastSeason && episode.episodeNumber <= lastEpisode)
                }()
                if releasedByDate || releasedByBoundary {
                    missedAired += 1
                }
            }
        }

        // Missing episode metadata means "unknown", never "caught up". Keeping the
        // previous confirmed lifecycle is safer than deriving from an empty response.
        guard hasCompleteEpisodeMap else { return nil }

        missedAired = max(missedAired, max(0, boundaryAiredCount - watchedAiredCount))

        let next = await resolveNextEpisode(for: showTargetID, watched: watched)

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
    @discardableResult
    public static func reconcileTrackingState(for showTargetID: String) async -> TrackedShowStatus? {
        guard let tracked = PlaybillStore.trackedShow(for: showTargetID),
              var show = PlaybillStore.entry(for: showTargetID),
              show.kind == .tvShow else { return nil }

        // Waiting is precisely the state most vulnerable to release/status changes,
        // so never trust its old snapshot when reconciling.
        let metadataIsStale = tracked.status == .waiting
            || show.seriesStatus == nil
            || show.lastAiredSeasonNumber == nil
            || Date().timeIntervalSince(show.cachedAt) > 3_600
        if metadataIsStale, let refreshed = try? await TMDBClient.fetchTVShow(id: show.tmdbID) {
            show = PlaybillStore.upsertCatalog(refreshed)
            await refreshCacheFromNetwork(showID: show.tmdbID)
        }

        await warmCache(for: showTargetID)
        guard let summary = await progressSummary(for: showTargetID) else { return tracked.status }

        let derived: TrackedShowStatus
        if summary.watchedEpisodeCount == 0 {
            derived = .planToWatch
        } else if summary.missedAiredCount > 0 {
            derived = .watching
        } else {
            let normalized = show.seriesStatus?.lowercased() ?? ""
            let hasEnded = normalized == "ended"
                || normalized == "canceled"
                || (show.seriesInProduction == false && show.nextEpisodeAirDate == nil)
            derived = hasEnded ? .completed : .waiting
        }

        PlaybillStore.updateTrackedShowStatus(targetID: showTargetID, status: derived)
        return derived
    }

    public static func seasonRows(
        for showTargetID: String
    ) async -> [(season: TMDBSeasonSummary, episodes: [TMDBEpisodeSummary])] {
        guard let show = PlaybillStore.entry(for: showTargetID), show.kind == .tvShow else { return [] }
        guard PlaybillPreferencesStore.isConfigured else { return [] }

        guard await ensureSeasonsLoaded(showID: show.tmdbID),
              let seasons = seasonCache[show.tmdbID] else { return [] }

        var rows: [(TMDBSeasonSummary, [TMDBEpisodeSummary])] = []
        for season in seasons where season.seasonNumber > 0 {
            if let episodes = await ensureEpisodesLoaded(showID: show.tmdbID, season: season.seasonNumber) {
                rows.append((season, episodes))
            }
        }
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
                if !watchedSet.contains(episodeID) {
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
    ) {
        guard let show = PlaybillStore.entry(for: showTargetID), show.kind == .tvShow else { return }

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

        PlaybillStore.logWatchBatch(targetIDs: targetIDs, watchedAt: watchedAt, source: .manual)
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
                if let airDate = episode.airDate, airDate < today {
                    missedAired += 1
                }
            }
        }
        return missedAired
    }

    // MARK: - Private

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
    private static func ensureSeasonsLoaded(showID: Int) async -> Bool {
        hydrateCache(showID: showID)
        if seasonCache[showID] != nil { return true }
        guard PlaybillPreferencesStore.isConfigured else { return false }
        if let seasons = try? await TMDBClient.fetchSeasonSummaries(showID: showID) {
            seasonCache[showID] = seasons
            persistCache(showID: showID)
            return true
        }
        return false
    }

    @discardableResult
    private static func ensureEpisodesLoaded(showID: Int, season: Int) async -> [TMDBEpisodeSummary]? {
        hydrateCache(showID: showID)
        let key = episodeCacheKey(showID: showID, season: season)
        if let cached = episodeCache[key] { return cached }
        guard PlaybillPreferencesStore.isConfigured else { return nil }
        if let episodes = try? await TMDBClient.fetchSeasonEpisodes(showID: showID, season: season) {
            episodeCache[key] = episodes
            persistCache(showID: showID)
            return episodes
        }
        return nil
    }

    private static func episodeCacheKey(showID: Int, season: Int) -> String {
        "\(showID):\(season)"
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
        if let snapshot = PlaybillStore.showMetadataSnapshot(for: CatalogEntry.showID(showID)) {
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

        // Migration fallback: older databases already contain catalog episodes even
        // though they predate persistent season snapshots.
        let showTargetID = CatalogEntry.showID(showID)
        let episodes = PlaybillStore.rawDatabase().catalog.values.filter {
            $0.kind == .episode && $0.parentShowID == showTargetID && $0.seasonNumber != nil && $0.episodeNumber != nil
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
                episodeCount: rows.compactMap(\.episodeNumber).max() ?? rows.count,
                name: "Season \(season)"
            )
        }
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
            cachedAt: Date()
        )
        _ = PlaybillStore.upsertCatalog(fallback)
        return fallback
    }
}
