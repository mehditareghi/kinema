import Foundation

public enum TMDBImageSize: String, Sendable {
    case posterW342 = "w342"
    case posterW500 = "w500"
    case backdropW780 = "w780"
}

public struct TMDBSeasonSummary: Sendable {
    public let seasonNumber: Int
    public let episodeCount: Int
    public let name: String?
}

public struct TMDBEpisodeSummary: Sendable {
    public let episodeNumber: Int
    public let name: String
    public let airDate: Date?
    public let runtimeMinutes: Int?
    public let stillPath: String?
}

public enum TMDBClientError: Error, LocalizedError {
    case missingAPIKey
    case invalidResponse
    case httpStatus(Int)
    case notFound
    case networkUnavailable

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "Add your TMDB API key in Preferences → Playbill."
        case .invalidResponse: return "Could not read TMDB response."
        case .httpStatus(let code): return "TMDB request failed (HTTP \(code))."
        case .notFound: return "Title not found on TMDB."
        case .networkUnavailable: return "Connect to refresh or discover Playbill titles. Your saved data is still available."
        }
    }
}

@MainActor
public enum TMDBClient {
    private static let baseURL = URL(string: "https://api.themoviedb.org/3")!

    public static func posterURL(path: String?, size: TMDBImageSize = .posterW500) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/\(size.rawValue)\(path)")
    }

    public static func search(query: String) async throws -> [PlaybillSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let json = try await request(path: "search/multi", queryItems: [
            URLQueryItem(name: "query", value: trimmed),
            URLQueryItem(name: "include_adult", value: "false")
        ])
        guard let results = json["results"] as? [[String: Any]] else { return [] }

        return results.compactMap { item in
            guard let mediaType = item["media_type"] as? String else { return nil }
            switch mediaType {
            case "movie":
                guard let id = item["id"] as? Int,
                      let title = item["title"] as? String else { return nil }
                let year = yearFromDate(item["release_date"] as? String)
                return PlaybillSearchResult(
                    id: CatalogEntry.movieID(id),
                    kind: .movie,
                    tmdbID: id,
                    title: title,
                    subtitle: nil,
                    year: year,
                    overview: item["overview"] as? String,
                    posterPath: item["poster_path"] as? String
                )
            case "tv":
                guard let id = item["id"] as? Int,
                      let title = item["name"] as? String else { return nil }
                let year = yearFromDate(item["first_air_date"] as? String)
                return PlaybillSearchResult(
                    id: CatalogEntry.showID(id),
                    kind: .tvShow,
                    tmdbID: id,
                    title: title,
                    subtitle: nil,
                    year: year,
                    overview: item["overview"] as? String,
                    posterPath: item["poster_path"] as? String
                )
            default:
                return nil
            }
        }
    }

    public static func fetchMovie(id: Int) async throws -> CatalogEntry {
        let json = try await request(path: "movie/\(id)")
        return catalogEntryFromMovie(json, id: id)
    }

    public static func fetchTVShow(id: Int) async throws -> CatalogEntry {
        let json = try await request(path: "tv/\(id)")
        return catalogEntryFromShow(json, id: id)
    }

    public static func fetchEpisode(showID: Int, season: Int, episode: Int) async throws -> CatalogEntry {
        let json = try await request(path: "tv/\(showID)/season/\(season)/episode/\(episode)")
        let showJSON = try await request(path: "tv/\(showID)")
        let showTitle = showJSON["name"] as? String ?? "Series"
        return catalogEntryFromEpisode(json, showID: showID, showTitle: showTitle, season: season, episode: episode)
    }

    public static func fetchSeasonSummaries(showID: Int) async throws -> [TMDBSeasonSummary] {
        let json = try await request(path: "tv/\(showID)")
        guard let seasons = json["seasons"] as? [[String: Any]] else { return [] }
        return seasons.compactMap { season in
            guard let number = season["season_number"] as? Int else { return nil }
            return TMDBSeasonSummary(
                seasonNumber: number,
                episodeCount: season["episode_count"] as? Int ?? 0,
                name: season["name"] as? String
            )
        }
        .sorted { $0.seasonNumber < $1.seasonNumber }
    }

    public static func fetchSeasonEpisodes(showID: Int, season: Int) async throws -> [TMDBEpisodeSummary] {
        let json = try await request(path: "tv/\(showID)/season/\(season)")
        guard let episodes = json["episodes"] as? [[String: Any]] else { return [] }
        return episodes.compactMap { episode in
            guard let number = episode["episode_number"] as? Int else { return nil }
            return TMDBEpisodeSummary(
                episodeNumber: number,
                name: episode["name"] as? String ?? "Episode \(number)",
                airDate: dateFromString(episode["air_date"] as? String),
                runtimeMinutes: episode["runtime"] as? Int,
                stillPath: episode["still_path"] as? String
            )
        }
        .sorted { $0.episodeNumber < $1.episodeNumber }
    }

    public static func catalogEntry(from result: PlaybillSearchResult) async throws -> CatalogEntry {
        switch result.kind {
        case .movie:
            return try await fetchMovie(id: result.tmdbID)
        case .tvShow:
            return try await fetchTVShow(id: result.tmdbID)
        case .episode:
            throw TMDBClientError.notFound
        }
    }

    public static func searchBestMatch(title: String, year: Int? = nil, kind: PlaybillMediaKind) async throws -> PlaybillSearchResult? {
        let results = try await search(query: title)
        let filtered = results.filter { candidate in
            switch kind {
            case .movie: return candidate.kind == .movie
            case .tvShow, .episode: return candidate.kind == .tvShow
            }
        }
        guard !filtered.isEmpty else { return nil }

        if let year {
            if let exact = filtered.first(where: { $0.year == year }) {
                return exact
            }
        }
        return filtered.first
    }

    private static func request(path: String, queryItems: [URLQueryItem] = []) async throws -> [String: Any] {
        guard PlaybillPreferencesStore.isConfigured else {
            throw TMDBClientError.missingAPIKey
        }

        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        var items = queryItems
        items.append(URLQueryItem(name: "api_key", value: PlaybillPreferencesStore.tmdbAPIKey))
        components.queryItems = items

        guard let url = components.url else { throw TMDBClientError.invalidResponse }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where [
            .notConnectedToInternet,
            .networkConnectionLost,
            .cannotFindHost,
            .cannotConnectToHost,
            .timedOut
        ].contains(error.code) {
            throw TMDBClientError.networkUnavailable
        }
        guard let http = response as? HTTPURLResponse else { throw TMDBClientError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw TMDBClientError.httpStatus(http.statusCode) }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TMDBClientError.invalidResponse
        }
        return json
    }

    private static func yearFromDate(_ value: String?) -> Int? {
        guard let value, value.count >= 4 else { return nil }
        return Int(value.prefix(4))
    }

    private static func dateFromString(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private static func genreNames(_ json: [String: Any]) -> [String] {
        (json["genres"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
    }

    private static func catalogEntryFromMovie(_ json: [String: Any], id: Int) -> CatalogEntry {
        CatalogEntry(
            id: CatalogEntry.movieID(id),
            kind: .movie,
            tmdbID: id,
            parentShowID: nil,
            title: json["title"] as? String ?? "Movie",
            subtitle: nil,
            year: yearFromDate(json["release_date"] as? String),
            overview: json["overview"] as? String,
            posterPath: json["poster_path"] as? String,
            backdropPath: json["backdrop_path"] as? String,
            genres: genreNames(json),
            runtimeMinutes: json["runtime"] as? Int,
            seasonNumber: nil,
            episodeNumber: nil,
            cachedAt: Date()
        )
    }

    private static func catalogEntryFromShow(_ json: [String: Any], id: Int) -> CatalogEntry {
        let nextEpisode = json["next_episode_to_air"] as? [String: Any]
        let lastEpisode = json["last_episode_to_air"] as? [String: Any]
        return CatalogEntry(
            id: CatalogEntry.showID(id),
            kind: .tvShow,
            tmdbID: id,
            parentShowID: nil,
            title: json["name"] as? String ?? "Series",
            subtitle: nil,
            year: yearFromDate(json["first_air_date"] as? String),
            overview: json["overview"] as? String,
            posterPath: json["poster_path"] as? String,
            backdropPath: json["backdrop_path"] as? String,
            genres: genreNames(json),
            runtimeMinutes: (json["episode_run_time"] as? [Int])?.first,
            seasonNumber: nil,
            episodeNumber: nil,
            cachedAt: Date(),
            seriesStatus: json["status"] as? String,
            seriesInProduction: json["in_production"] as? Bool,
            nextEpisodeAirDate: dateFromString(nextEpisode?["air_date"] as? String),
            totalEpisodeCount: json["number_of_episodes"] as? Int,
            lastAiredSeasonNumber: lastEpisode?["season_number"] as? Int,
            lastAiredEpisodeNumber: lastEpisode?["episode_number"] as? Int
        )
    }

    private static func catalogEntryFromEpisode(
        _ json: [String: Any],
        showID: Int,
        showTitle: String,
        season: Int,
        episode: Int
    ) -> CatalogEntry {
        CatalogEntry(
            id: CatalogEntry.episodeID(showTmdbID: showID, season: season, episode: episode),
            kind: .episode,
            tmdbID: showID,
            parentShowID: CatalogEntry.showID(showID),
            title: showTitle,
            subtitle: json["name"] as? String,
            year: yearFromDate(json["air_date"] as? String),
            overview: json["overview"] as? String,
            posterPath: json["still_path"] as? String ?? json["poster_path"] as? String,
            backdropPath: json["still_path"] as? String,
            genres: [],
            runtimeMinutes: json["runtime"] as? Int,
            seasonNumber: season,
            episodeNumber: episode,
            cachedAt: Date()
        )
    }
}
