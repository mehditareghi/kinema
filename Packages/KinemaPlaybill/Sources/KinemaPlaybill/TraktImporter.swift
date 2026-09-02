import Foundation

public enum TraktImportError: Error, LocalizedError {
    case invalidFormat
    case missingAPIKey

    public var errorDescription: String? {
        switch self {
        case .invalidFormat: return "This file does not look like a Trakt export."
        case .missingAPIKey: return "Add your TMDB API key to enrich imported titles."
        }
    }
}

@MainActor
public enum TraktImporter {
    public struct ImportProgress: Sendable, Equatable {
        public var processed: Int
        public var total: Int
        public var imported: Int
        public var message: String

        public init(processed: Int, total: Int, imported: Int, message: String) {
            self.processed = processed
            self.total = total
            self.imported = imported
            self.message = message
        }

        public var fraction: Double {
            guard total > 0 else { return 0 }
            return min(1, max(0, Double(processed) / Double(total)))
        }
    }

    /// Imports Trakt history JSON (export format with `watched_at`, `type`, nested movie/show/episode).
    public static func importHistory(
        from data: Data,
        progress: ((ImportProgress) -> Void)? = nil
    ) async throws -> Int {
        let summary = try await importHistorySummary(from: data, progress: progress)
        return summary.added
    }

    public static func importHistorySummary(
        from data: Data,
        progress: ((ImportProgress) -> Void)? = nil
    ) async throws -> TraktImportSummary {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw TraktImportError.invalidFormat
        }

        var summary = TraktImportSummary()
        progress?(ImportProgress(
            processed: 0,
            total: json.count,
            imported: summary.handled,
            message: "Reading \(json.count) Trakt entries..."
        ))

        for (index, row) in json.enumerated() {
            let processed = index + 1
            do {
                if let movie = row["movie"] as? [String: Any] {
                    guard let watchedAt = parseDate(row["watched_at"]) ?? parseDate(row["last_watched_at"]) else {
                        progress?(ImportProgress(
                            processed: processed,
                            total: json.count,
                            imported: summary.handled,
                            message: progressMessage(summary: summary, processed: processed)
                        ))
                        continue
                    }
                    if let count = try await importMovie(movie, watchedAt: watchedAt) {
                        summary.added += count.added
                        summary.alreadyPresent += count.alreadyPresent
                    }
                    progress?(ImportProgress(
                        processed: processed,
                        total: json.count,
                        imported: summary.handled,
                        message: progressMessage(summary: summary, processed: processed)
                    ))
                    await Task.yield()
                    continue
                }

                if let episode = row["episode"] as? [String: Any],
                   let show = row["show"] as? [String: Any] {
                    guard let watchedAt = parseDate(row["watched_at"]) ?? parseDate(row["last_watched_at"]) else {
                        progress?(ImportProgress(
                            processed: processed,
                            total: json.count,
                            imported: summary.handled,
                            message: progressMessage(summary: summary, processed: processed)
                        ))
                        continue
                    }
                    if let count = try await importEpisode(episode, show: show, watchedAt: watchedAt) {
                        summary.added += count.added
                        summary.alreadyPresent += count.alreadyPresent
                    }
                    progress?(ImportProgress(
                        processed: processed,
                        total: json.count,
                        imported: summary.handled,
                        message: progressMessage(summary: summary, processed: processed)
                    ))
                    await Task.yield()
                    continue
                }

                if let show = row["show"] as? [String: Any],
                   let seasons = row["seasons"] as? [[String: Any]] {
                    let count = try await importWatchedShow(show, seasons: seasons)
                    summary.added += count.added
                    summary.alreadyPresent += count.alreadyPresent
                    progress?(ImportProgress(
                        processed: processed,
                        total: json.count,
                        imported: summary.handled,
                        message: progressMessage(summary: summary, processed: processed)
                    ))
                    await Task.yield()
                    continue
                }

                if let show = row["show"] as? [String: Any], row["episode"] == nil {
                    guard let watchedAt = parseDate(row["watched_at"]) ?? parseDate(row["last_watched_at"]) else {
                        progress?(ImportProgress(
                            processed: processed,
                            total: json.count,
                            imported: summary.handled,
                            message: progressMessage(summary: summary, processed: processed)
                        ))
                        continue
                    }
                    if let count = try await importShow(show, watchedAt: watchedAt) {
                        summary.added += count.added
                        summary.alreadyPresent += count.alreadyPresent
                    }
                    progress?(ImportProgress(
                        processed: processed,
                        total: json.count,
                        imported: summary.handled,
                        message: progressMessage(summary: summary, processed: processed)
                    ))
                }
            } catch {
                progress?(ImportProgress(
                    processed: processed,
                    total: json.count,
                    imported: summary.handled,
                    message: "Skipped row \(processed): \(error.localizedDescription). \(progressMessage(summary: summary, processed: processed))"
                ))
            }
            await Task.yield()
        }

        summary.repaired = PlaybillStore.repairWatchedSeriesTracking()
        for tracked in PlaybillStore.trackedShows() {
            guard let show = PlaybillStore.entry(for: tracked.targetID), show.kind == .tvShow else { continue }
            PlaybillShowProgress.invalidateCachedMetadata(showID: show.tmdbID)
        }
        progress?(ImportProgress(
            processed: json.count,
            total: json.count,
            imported: summary.handled,
            message: finalMessage(summary)
        ))
        return summary
    }

    private static func importMovie(_ movie: [String: Any], watchedAt: Date) async throws -> TraktImportSummary? {
        let ids = movie["ids"] as? [String: Any]
        let titleInfo = titleAndYear(from: movie, fallbackTitle: "Movie")

        let entry: CatalogEntry
        if let tmdbID = ids?["tmdb"] as? Int {
            entry = if PlaybillPreferencesStore.isConfigured {
                (try? await TMDBClient.fetchMovie(id: tmdbID))
                    ?? fallbackMovieEntry(tmdbID: tmdbID, titleInfo: titleInfo)
            } else {
                fallbackMovieEntry(tmdbID: tmdbID, titleInfo: titleInfo)
            }
        } else if PlaybillPreferencesStore.isConfigured,
                  let match = try await TMDBClient.searchBestMatch(
                    title: titleInfo.title,
                    year: titleInfo.year,
                    kind: .movie
                  ) {
            entry = try await TMDBClient.catalogEntry(from: match)
        } else {
            return nil
        }

        _ = PlaybillStore.upsertCatalog(entry)
        return logImportedWatch(targetID: entry.id, watchedAt: watchedAt)
    }

    private static func importShow(_ show: [String: Any], watchedAt: Date) async throws -> TraktImportSummary? {
        let ids = show["ids"] as? [String: Any]
        let titleInfo = titleAndYear(from: show, fallbackTitle: "Series")

        let entry: CatalogEntry
        if let tmdbID = ids?["tmdb"] as? Int {
            entry = if PlaybillPreferencesStore.isConfigured {
                (try? await TMDBClient.fetchTVShow(id: tmdbID))
                    ?? fallbackShowEntry(tmdbID: tmdbID, titleInfo: titleInfo)
            } else {
                fallbackShowEntry(tmdbID: tmdbID, titleInfo: titleInfo)
            }
        } else if PlaybillPreferencesStore.isConfigured,
                  let match = try await TMDBClient.searchBestMatch(
                    title: titleInfo.title,
                    year: titleInfo.year,
                    kind: .tvShow
                  ) {
            entry = try await TMDBClient.catalogEntry(from: match)
        } else {
            return nil
        }

        _ = PlaybillStore.upsertCatalog(entry)
        trackShowAsWatchingIfNeeded(entry.id)
        return TraktImportSummary(added: 1)
    }

    private static func importWatchedShow(_ show: [String: Any], seasons: [[String: Any]]) async throws -> TraktImportSummary {
        let showIDs = show["ids"] as? [String: Any]
        let titleInfo = titleAndYear(from: show, fallbackTitle: "Series")

        let showEntry: CatalogEntry
        if let tmdbID = showIDs?["tmdb"] as? Int {
            showEntry = if PlaybillPreferencesStore.isConfigured {
                (try? await TMDBClient.fetchTVShow(id: tmdbID))
                    ?? fallbackShowEntry(tmdbID: tmdbID, titleInfo: titleInfo)
            } else {
                fallbackShowEntry(tmdbID: tmdbID, titleInfo: titleInfo)
            }
        } else if PlaybillPreferencesStore.isConfigured,
                  let match = try await TMDBClient.searchBestMatch(
                    title: titleInfo.title,
                    year: titleInfo.year,
                    kind: .tvShow
                  ) {
            showEntry = try await TMDBClient.catalogEntry(from: match)
        } else {
            return TraktImportSummary()
        }

        _ = PlaybillStore.upsertCatalog(showEntry)
        trackShowAsWatchingIfNeeded(showEntry.id)

        var summary = TraktImportSummary()
        for seasonRow in seasons {
            let seasonNumber = seasonRow["number"] as? Int ?? 0
            guard seasonNumber > 0,
                  let episodes = seasonRow["episodes"] as? [[String: Any]] else {
                continue
            }

            for episodeRow in episodes {
                let episodeNumber = episodeRow["number"] as? Int ?? 0
                guard episodeNumber > 0 else { continue }
                let watchedAt = parseDate(episodeRow["last_watched_at"])
                    ?? parseDate(seasonRow["last_watched_at"])
                    ?? parseDate(show["last_watched_at"])
                    ?? Date()
                let pseudoEpisode: [String: Any] = [
                    "season": seasonNumber,
                    "number": episodeNumber
                ]
                if let count = try await importEpisode(pseudoEpisode, show: show, watchedAt: watchedAt) {
                    summary.added += count.added
                    summary.alreadyPresent += count.alreadyPresent
                }
                await Task.yield()
            }
        }

        return summary
    }

    private static func importEpisode(
        _ episode: [String: Any],
        show: [String: Any],
        watchedAt: Date
    ) async throws -> TraktImportSummary? {
        let showIDs = show["ids"] as? [String: Any]
        let titleInfo = titleAndYear(from: show, fallbackTitle: "Series")
        let season = episode["season"] as? Int ?? 0
        let number = episode["number"] as? Int ?? 0
        guard season > 0, number > 0 else { return nil }

        let entry: CatalogEntry
        if let tmdbShowID = showIDs?["tmdb"] as? Int {
            let showEntry = if PlaybillPreferencesStore.isConfigured {
                (try? await TMDBClient.fetchTVShow(id: tmdbShowID))
                    ?? fallbackShowEntry(tmdbID: tmdbShowID, titleInfo: titleInfo)
            } else {
                fallbackShowEntry(tmdbID: tmdbShowID, titleInfo: titleInfo)
            }
            _ = PlaybillStore.upsertCatalog(showEntry)
            trackShowAsWatchingIfNeeded(showEntry.id)
            entry = if PlaybillPreferencesStore.isConfigured {
                (try? await TMDBClient.fetchEpisode(showID: tmdbShowID, season: season, episode: number))
                    ?? fallbackEpisodeEntry(show: showEntry, season: season, episode: number)
            } else {
                fallbackEpisodeEntry(show: showEntry, season: season, episode: number)
            }
        } else if PlaybillPreferencesStore.isConfigured,
                  let match = try await TMDBClient.searchBestMatch(
                    title: titleInfo.title,
                    year: titleInfo.year,
                    kind: .tvShow
                  ) {
            if let showEntry = try? await TMDBClient.fetchTVShow(id: match.tmdbID) {
                _ = PlaybillStore.upsertCatalog(showEntry)
                trackShowAsWatchingIfNeeded(showEntry.id)
            }
            entry = try await TMDBClient.fetchEpisode(
                showID: match.tmdbID,
                season: season,
                episode: number
            )
        } else {
            return nil
        }

        _ = PlaybillStore.upsertCatalog(entry)
        if let showID = entry.parentShowID {
            trackShowAsWatchingIfNeeded(showID)
        }
        return logImportedWatch(targetID: entry.id, watchedAt: watchedAt)
    }

    private static func logImportedWatch(targetID: String, watchedAt: Date) -> TraktImportSummary {
        if PlaybillStore.hasFullWatch(targetID: targetID, watchedAt: watchedAt, source: .importTrakt) {
            return TraktImportSummary(alreadyPresent: 1)
        }
        if PlaybillStore.logWatch(targetID: targetID, watchedAt: watchedAt, source: .importTrakt) != nil {
            return TraktImportSummary(added: 1)
        }
        if PlaybillStore.hasFullWatch(targetID: targetID, watchedAt: watchedAt, source: .importTrakt) {
            return TraktImportSummary(alreadyPresent: 1)
        }
        return TraktImportSummary()
    }

    private static func progressMessage(summary: TraktImportSummary, processed: Int) -> String {
        let existing = summary.alreadyPresent > 0 ? ", \(summary.alreadyPresent) already present" : ""
        return "Imported \(summary.added)\(existing) of \(processed) resolved entries..."
    }

    private static func finalMessage(_ summary: TraktImportSummary) -> String {
        var parts = ["Imported \(summary.added) new Trakt \(summary.added == 1 ? "entry" : "entries")"]
        if summary.alreadyPresent > 0 {
            parts.append("\(summary.alreadyPresent) already present")
        }
        if summary.repaired > 0 {
            parts.append("repaired \(summary.repaired) Playbill \(summary.repaired == 1 ? "record" : "records")")
        }
        return parts.joined(separator: ", ") + "."
    }

    private static func fallbackShowEntry(
        tmdbID: Int,
        titleInfo: (title: String, year: Int?)
    ) -> CatalogEntry {
        CatalogEntry(
            id: CatalogEntry.showID(tmdbID),
            kind: .tvShow,
            tmdbID: tmdbID,
            title: titleInfo.title,
            year: titleInfo.year
        )
    }

    private static func fallbackMovieEntry(
        tmdbID: Int,
        titleInfo: (title: String, year: Int?)
    ) -> CatalogEntry {
        CatalogEntry(
            id: CatalogEntry.movieID(tmdbID),
            kind: .movie,
            tmdbID: tmdbID,
            title: titleInfo.title,
            year: titleInfo.year
        )
    }

    private static func fallbackEpisodeEntry(
        show: CatalogEntry,
        season: Int,
        episode: Int
    ) -> CatalogEntry {
        CatalogEntry(
            id: CatalogEntry.episodeID(showTmdbID: show.tmdbID, season: season, episode: episode),
            kind: .episode,
            tmdbID: show.tmdbID,
            parentShowID: show.id,
            title: show.title,
            subtitle: String(format: "S%02dE%02d", season, episode),
            year: show.year,
            posterPath: show.posterPath,
            backdropPath: show.backdropPath,
            genres: show.genres,
            runtimeMinutes: show.runtimeMinutes,
            seasonNumber: season,
            episodeNumber: episode
        )
    }

    private static func trackShowAsWatchingIfNeeded(_ showID: String) {
        if let tracked = PlaybillStore.trackedShow(for: showID) {
            if tracked.status == .planToWatch {
                PlaybillStore.updateTrackedShowStatus(targetID: showID, status: .watching)
            }
        } else {
            _ = PlaybillStore.trackShow(targetID: showID, status: .watching)
        }
    }

    private static func parseDate(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    private static func titleAndYear(
        from payload: [String: Any],
        fallbackTitle: String
    ) -> (title: String, year: Int?) {
        let rawTitle = (payload["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let explicitYear = payload["year"] as? Int
        guard var title = rawTitle, !title.isEmpty else {
            return (fallbackTitle, explicitYear)
        }

        guard title.hasSuffix(")") else {
            return (title, explicitYear)
        }

        guard let openParen = title.lastIndex(of: "(") else {
            return (title, explicitYear)
        }

        let yearText = title[title.index(after: openParen)..<title.index(before: title.endIndex)]
        guard yearText.count == 4, let suffixYear = Int(yearText) else {
            return (title, explicitYear)
        }

        title = String(title[..<openParen]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (title.isEmpty ? fallbackTitle : title, explicitYear ?? suffixYear)
    }
}
