import Foundation
import KinemaCore
import KinemaMedia

@MainActor
public enum PlaybillMatcher {
    public static func candidates(for url: URL, title: String) async -> [PlaybillMatchCandidate] {
        guard PlaybillPreferencesStore.isConfigured else { return [] }

        let mediaID = WatchProgressStore.mediaID(for: url)

        if let link = PlaybillStore.link(for: mediaID), let entry = PlaybillStore.entry(for: link.targetID) {
            return [PlaybillMatchCandidate(
                result: PlaybillSearchResult(
                    id: entry.id,
                    kind: entry.kind,
                    tmdbID: entry.tmdbID,
                    title: entry.title,
                    subtitle: entry.subtitle,
                    year: entry.year,
                    overview: entry.overview,
                    posterPath: entry.posterPath
                ),
                confidence: link.confirmedByUser ? .manual : link.matchConfidence
            )]
        }

        if let episode = MediaSeriesOrganizer.episodeIdentity(from: url) {
            return await episodeCandidates(episode: episode, mediaID: mediaID)
        }

        return await movieCandidates(title: cleanedTitle(from: title, url: url))
    }

    public static func resolveAndLink(
        url: URL,
        candidate: PlaybillSearchResult,
        confirmedByUser: Bool
    ) async throws -> CatalogEntry {
        let mediaID = WatchProgressStore.mediaID(for: url)
        let entry: CatalogEntry

        switch candidate.kind {
        case .movie, .tvShow:
            entry = try await TMDBClient.catalogEntry(from: candidate)
        case .episode:
            throw TMDBClientError.notFound
        }

        _ = PlaybillStore.upsertCatalog(entry)
        PlaybillStore.linkMedia(
            mediaID: mediaID,
            targetID: entry.id,
            confidence: confirmedByUser ? .manual : .high,
            confirmedByUser: confirmedByUser
        )

        if entry.kind == .tvShow {
            let showKey = showKeyFromURL(url) ?? entry.title.lowercased()
            PlaybillStore.rememberShow(showKey: showKey, tmdbShowID: entry.tmdbID)
        }

        return entry
    }

    public static func resolveEpisodeAndLink(
        url: URL,
        showTmdbID: Int,
        season: Int,
        episode: Int,
        confirmedByUser: Bool
    ) async throws -> CatalogEntry {
        let mediaID = WatchProgressStore.mediaID(for: url)
        let entry = try await TMDBClient.fetchEpisode(showID: showTmdbID, season: season, episode: episode)
        _ = PlaybillStore.upsertCatalog(entry)

        if let showEntry = try? await TMDBClient.fetchTVShow(id: showTmdbID) {
            _ = PlaybillStore.upsertCatalog(showEntry)
        }

        PlaybillStore.linkMedia(
            mediaID: mediaID,
            targetID: entry.id,
            confidence: confirmedByUser ? .manual : .high,
            confirmedByUser: confirmedByUser
        )

        if let showKey = showKeyFromURL(url) {
            PlaybillStore.rememberShow(showKey: showKey, tmdbShowID: showTmdbID)
        }

        return entry
    }

    public static func autoResolveTargetID(for url: URL, title: String) async -> String? {
        switch await scrobbleResolution(for: url, title: title) {
        case .autoLogged(let targetID):
            return targetID
        case .needsConfirmation, .noMatch:
            return nil
        }
    }

    public static func scrobbleResolution(for url: URL, title: String) async -> PlaybillScrobbleResolution {
        if let linked = PlaybillStore.targetID(for: WatchProgressStore.mediaID(for: url)) {
            return .autoLogged(targetID: linked)
        }

        if let episode = MediaSeriesOrganizer.episodeIdentity(from: url),
           let showKey = showKeyFromEpisode(episode),
           let memory = PlaybillStore.showMemory(matchingKey: showKey) {
            let targetID = CatalogEntry.episodeID(
                showTmdbID: memory.tmdbShowID,
                season: episode.season,
                episode: episode.episode
            )
            if PlaybillStore.entry(for: targetID) != nil {
                return .autoLogged(targetID: targetID)
            }
            if let entry = try? await TMDBClient.fetchEpisode(
                showID: memory.tmdbShowID,
                season: episode.season,
                episode: episode.episode
            ) {
                _ = PlaybillStore.upsertCatalog(entry)
                PlaybillStore.linkMedia(
                    mediaID: WatchProgressStore.mediaID(for: url),
                    targetID: entry.id,
                    confidence: .high,
                    confirmedByUser: false
                )
                return .autoLogged(targetID: entry.id)
            }
        }

        let matches = await candidates(for: url, title: title)
        guard let best = matches.first else { return .noMatch }

        if best.confidence == .high || best.confidence == .manual {
            if let entry = try? await catalogEntry(for: best.result, url: url) {
                _ = PlaybillStore.upsertCatalog(entry)
                PlaybillStore.linkMedia(
                    mediaID: WatchProgressStore.mediaID(for: url),
                    targetID: entry.id,
                    confidence: best.confidence,
                    confirmedByUser: best.confidence == .manual
                )
                if entry.kind == .episode, let showKey = showKeyFromURL(url) {
                    PlaybillStore.rememberShow(showKey: showKey, tmdbShowID: entry.tmdbID)
                }
                return .autoLogged(targetID: entry.id)
            }
            return .autoLogged(targetID: best.result.id)
        }

        let confirmable = matches.filter { $0.confidence == .medium }
        guard !confirmable.isEmpty else { return .noMatch }
        return .needsConfirmation(confirmable)
    }

    @discardableResult
    public static func confirmCandidate(
        url: URL,
        candidate: PlaybillMatchCandidate,
        rememberShow: Bool = true
    ) async throws -> CatalogEntry {
        let entry = try await catalogEntry(for: candidate.result, url: url)
        _ = PlaybillStore.upsertCatalog(entry)
        PlaybillStore.linkMedia(
            mediaID: WatchProgressStore.mediaID(for: url),
            targetID: entry.id,
            confidence: .manual,
            confirmedByUser: true
        )

        if rememberShow, entry.kind == .episode, let showKey = showKeyFromURL(url) {
            PlaybillStore.rememberShow(showKey: showKey, tmdbShowID: entry.tmdbID)
        } else if rememberShow, entry.kind == .tvShow, let showKey = showKeyFromURL(url) {
            PlaybillStore.rememberShow(showKey: showKey, tmdbShowID: entry.tmdbID)
        }

        return entry
    }

    private static func catalogEntry(for result: PlaybillSearchResult, url: URL) async throws -> CatalogEntry {
        _ = url
        if result.kind == .episode, let parsed = parseEpisodeTargetID(result.id) {
            return try await fetchEpisodeEntry(
                showID: parsed.showTmdbID,
                season: parsed.season,
                episode: parsed.episode
            )
        }
        return try await TMDBClient.catalogEntry(from: result)
    }

    private static func fetchEpisodeEntry(showID: Int, season: Int, episode: Int) async throws -> CatalogEntry {
        let entry = try await TMDBClient.fetchEpisode(showID: showID, season: season, episode: episode)
        if let showEntry = try? await TMDBClient.fetchTVShow(id: showID) {
            _ = PlaybillStore.upsertCatalog(showEntry)
        }
        return entry
    }

    private static func parseEpisodeTargetID(_ id: String) -> (showTmdbID: Int, season: Int, episode: Int)? {
        // tmdb:tv:1396:s1e1
        let parts = id.split(separator: ":")
        guard parts.count >= 4,
              parts[0] == "tmdb", parts[1] == "tv",
              let showID = Int(parts[2]) else { return nil }
        let episodePart = String(parts[3])
        guard episodePart.hasPrefix("s"),
              let eIndex = episodePart.firstIndex(of: "e") else { return nil }
        let seasonString = episodePart[episodePart.index(after: episodePart.startIndex)..<eIndex]
        let episodeString = episodePart[episodePart.index(after: eIndex)...]
        guard let season = Int(seasonString), let episode = Int(episodeString) else { return nil }
        return (showID, season, episode)
    }

    private static func episodeCandidates(episode: MediaEpisodeIdentity, mediaID: String) async -> [PlaybillMatchCandidate] {
        let showKey = showKeyFromEpisode(episode) ?? episode.showTitle.lowercased()

        if let memory = PlaybillStore.showMemory(matchingKey: showKey) {
            let targetID = CatalogEntry.episodeID(
                showTmdbID: memory.tmdbShowID,
                season: episode.season,
                episode: episode.episode
            )
            if let entry = PlaybillStore.entry(for: targetID) {
                return [PlaybillMatchCandidate(
                    result: searchResult(from: entry),
                    confidence: .high
                )]
            }
            if let fetched = try? await TMDBClient.fetchEpisode(
                showID: memory.tmdbShowID,
                season: episode.season,
                episode: episode.episode
            ) {
                _ = PlaybillStore.upsertCatalog(fetched)
                return [PlaybillMatchCandidate(result: searchResult(from: fetched), confidence: .high)]
            }
        }

        do {
            if let showMatch = try await TMDBClient.searchBestMatch(
                title: cleanedLookupTitle(episode.showTitle),
                kind: .tvShow
            ) {
                let entry = try await TMDBClient.fetchEpisode(
                    showID: showMatch.tmdbID,
                    season: episode.season,
                    episode: episode.episode
                )
                _ = PlaybillStore.upsertCatalog(entry)
                let confidence: MatchConfidence = normalized(cleanedLookupTitle(episode.showTitle)) == normalized(showMatch.title)
                    ? .high
                    : .medium
                return [PlaybillMatchCandidate(result: searchResult(from: entry), confidence: confidence)]
            }
        } catch {
            return []
        }

        return []
    }

    private static func movieCandidates(title: String) async -> [PlaybillMatchCandidate] {
        do {
            let lookupTitle = cleanedLookupTitle(title)
            let results = try await TMDBClient.search(query: lookupTitle).filter { $0.kind == .movie }
            return results.prefix(5).map { result in
                PlaybillMatchCandidate(
                    result: result,
                    confidence: normalized(lookupTitle) == normalized(result.title) ? .high : .medium
                )
            }
        } catch {
            return []
        }
    }

    private static func searchResult(from entry: CatalogEntry) -> PlaybillSearchResult {
        PlaybillSearchResult(
            id: entry.id,
            kind: entry.kind,
            tmdbID: entry.tmdbID,
            title: entry.displayTitle,
            subtitle: entry.subtitle,
            year: entry.year,
            overview: entry.overview,
            posterPath: entry.posterPath
        )
    }

    private static func cleanedTitle(from title: String, url: URL) -> String {
        let raw = title.isEmpty ? url.deletingPathExtension().lastPathComponent : title
        return cleanedLookupTitle(raw)
    }

    /// Remove common release metadata without guessing through the meaningful part
    /// of a title. This turns `Film.2025.2160p.WEB-DL` into `Film`, while keeping a
    /// genuine trailing-number title such as `Blade Runner 2049` intact.
    private static func cleanedLookupTitle(_ raw: String) -> String {
        let separated = raw
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        let tokens = separated.split { $0.isWhitespace }.map(String.init)
        guard !tokens.isEmpty else { return raw.trimmingCharacters(in: .whitespacesAndNewlines) }

        let noise = Set([
            "480p", "576p", "720p", "1080p", "1080i", "2160p", "4320p",
            "web", "webdl", "webrip", "bluray", "brrip", "bdrip", "hdrip", "dvdrip",
            "hdtv", "remux", "x264", "x265", "h264", "h265", "hevc", "av1",
            "hdr", "hdr10", "dolby", "vision", "dovi", "aac", "ac3", "dts", "atmos"
        ])
        var end = tokens.count
        for (index, token) in tokens.enumerated() {
            let normalizedToken = normalized(token)
            let isNoise = noise.contains(normalizedToken)
            let isReleaseYear = token.count == 4
                && Int(token).map { (1900...2099).contains($0) } == true
                && tokens[(index + 1)...].contains { noise.contains(normalized($0)) }
            if isNoise || isReleaseYear {
                end = index
                break
            }
        }
        let cleaned = tokens[..<end].joined(separator: " ")
        return cleaned.isEmpty ? tokens.joined(separator: " ") : cleaned
    }

    private static func normalized(_ value: String) -> String {
        value.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }

    private static func showKeyFromURL(_ url: URL) -> String? {
        guard let episode = MediaSeriesOrganizer.episodeIdentity(from: url) else { return nil }
        return showKeyFromEpisode(episode)
    }

    private static func showKeyFromEpisode(_ episode: MediaEpisodeIdentity) -> String? {
        MediaSeriesOrganizer.showKey(forTitle: episode.showTitle)
    }

    private static func showKeyFromTitle(_ title: String) -> String {
        MediaSeriesOrganizer.showKey(forTitle: title)
    }

    /// Whether a local file corresponds to a Playbill catalog entry (link, episode parse, or title).
    public static func matchesCatalogEntry(_ entry: CatalogEntry, url: URL) -> Bool {
        if inferredTargetID(for: url) == entry.id { return true }
        if PlaybillStore.targetID(for: WatchProgressStore.mediaID(for: url)) == entry.id {
            return true
        }

        switch entry.kind {
        case .episode:
            guard let episode = MediaSeriesOrganizer.episodeIdentity(from: url),
                  episode.season == entry.seasonNumber,
                  episode.episode == entry.episodeNumber else { return false }
            guard let showTmdbID = showTmdbID(fromEpisodeTargetID: entry.id) else { return false }

            if let showKey = showKeyFromEpisode(episode),
               let memory = PlaybillStore.showMemory(matchingKey: showKey),
               memory.tmdbShowID == showTmdbID {
                return true
            }

            if let parentID = entry.parentShowID,
               let show = PlaybillStore.entry(for: parentID),
               MediaSeriesOrganizer.showTitleMatches(episode.showTitle, catalogTitle: show.title) {
                return true
            }

            return false

        case .movie:
            let filename = normalized(url.deletingPathExtension().lastPathComponent)
            let title = normalized(entry.title)
            guard title.count >= 3 else { return false }
            return filename.contains(title)

        case .tvShow:
            return false
        }
    }

    private static func showTmdbID(fromEpisodeTargetID targetID: String) -> Int? {
        // tmdb:tv:123:s1e2
        let parts = targetID.split(separator: ":")
        guard parts.count >= 3, parts[0] == "tmdb", parts[1] == "tv" else { return nil }
        return Int(parts[2])
    }

    /// Resolves a Playbill target ID from a file link, show memory, or episode parse — no network.
    public static func inferredTargetID(for url: URL) -> String? {
        let mediaID = WatchProgressStore.mediaID(for: url)
        if let linked = PlaybillStore.targetID(for: mediaID) {
            return linked
        }
        guard let episode = MediaSeriesOrganizer.episodeIdentity(from: url),
              let showKey = showKeyFromEpisode(episode),
              let memory = PlaybillStore.showMemory(matchingKey: showKey) else { return nil }
        return CatalogEntry.episodeID(
            showTmdbID: memory.tmdbShowID,
            season: episode.season,
            episode: episode.episode
        )
    }
}
