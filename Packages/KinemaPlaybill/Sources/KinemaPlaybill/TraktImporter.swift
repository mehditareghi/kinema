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
    /// Imports Trakt history JSON (export format with `watched_at`, `type`, nested movie/show/episode).
    public static func importHistory(from data: Data) async throws -> Int {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw TraktImportError.invalidFormat
        }

        var imported = 0

        for row in json {
            guard let watchedAt = parseDate(row["watched_at"]) else { continue }

            if let movie = row["movie"] as? [String: Any] {
                if let count = try await importMovie(movie, watchedAt: watchedAt) {
                    imported += count
                }
                continue
            }

            if let episode = row["episode"] as? [String: Any],
               let show = row["show"] as? [String: Any] {
                if let count = try await importEpisode(episode, show: show, watchedAt: watchedAt) {
                    imported += count
                }
                continue
            }

            if let show = row["show"] as? [String: Any], row["episode"] == nil {
                if let count = try await importShow(show, watchedAt: watchedAt) {
                    imported += count
                }
            }
        }

        return imported
    }

    private static func importMovie(_ movie: [String: Any], watchedAt: Date) async throws -> Int? {
        let ids = movie["ids"] as? [String: Any]
        let title = movie["title"] as? String ?? "Movie"
        let year = movie["year"] as? Int

        let entry: CatalogEntry
        if let tmdbID = ids?["tmdb"] as? Int, PlaybillPreferencesStore.isConfigured {
            entry = try await TMDBClient.fetchMovie(id: tmdbID)
        } else if PlaybillPreferencesStore.isConfigured,
                  let match = try await TMDBClient.searchBestMatch(title: title, year: year, kind: .movie) {
            entry = try await TMDBClient.catalogEntry(from: match)
        } else {
            return nil
        }

        _ = PlaybillStore.upsertCatalog(entry)
        _ = PlaybillStore.logWatch(targetID: entry.id, watchedAt: watchedAt, source: .importTrakt)
        return 1
    }

    private static func importShow(_ show: [String: Any], watchedAt: Date) async throws -> Int? {
        let ids = show["ids"] as? [String: Any]
        let title = show["title"] as? String ?? "Series"
        let year = show["year"] as? Int

        let entry: CatalogEntry
        if let tmdbID = ids?["tmdb"] as? Int, PlaybillPreferencesStore.isConfigured {
            entry = try await TMDBClient.fetchTVShow(id: tmdbID)
        } else if PlaybillPreferencesStore.isConfigured,
                  let match = try await TMDBClient.searchBestMatch(title: title, year: year, kind: .tvShow) {
            entry = try await TMDBClient.catalogEntry(from: match)
        } else {
            return nil
        }

        _ = PlaybillStore.upsertCatalog(entry)
        _ = PlaybillStore.logWatch(targetID: entry.id, watchedAt: watchedAt, source: .importTrakt)
        return 1
    }

    private static func importEpisode(
        _ episode: [String: Any],
        show: [String: Any],
        watchedAt: Date
    ) async throws -> Int? {
        let showIDs = show["ids"] as? [String: Any]
        let season = episode["season"] as? Int ?? 0
        let number = episode["number"] as? Int ?? 0
        guard season > 0, number > 0 else { return nil }

        let entry: CatalogEntry
        if let tmdbShowID = showIDs?["tmdb"] as? Int, PlaybillPreferencesStore.isConfigured {
            entry = try await TMDBClient.fetchEpisode(showID: tmdbShowID, season: season, episode: number)
            if let showEntry = try? await TMDBClient.fetchTVShow(id: tmdbShowID) {
                _ = PlaybillStore.upsertCatalog(showEntry)
            }
        } else if PlaybillPreferencesStore.isConfigured,
                  let showTitle = show["title"] as? String,
                  let match = try await TMDBClient.searchBestMatch(title: showTitle, kind: .tvShow) {
            entry = try await TMDBClient.fetchEpisode(
                showID: match.tmdbID,
                season: season,
                episode: number
            )
        } else {
            return nil
        }

        _ = PlaybillStore.upsertCatalog(entry)
        _ = PlaybillStore.logWatch(targetID: entry.id, watchedAt: watchedAt, source: .importTrakt)
        return 1
    }

    private static func parseDate(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
