import Foundation
import KinemaCore

public struct SubtitleMatch: Sendable, Identifiable {
    public let id: URL
    public let url: URL
    public let label: String
    public let languageCode: String?

    public init(url: URL, label: String, languageCode: String? = nil) {
        self.id = url
        self.url = url
        self.label = label
        self.languageCode = languageCode
    }
}

public enum SubtitleFileMatcher {
    /// Sidecar extensions Kinema treats as first-class subtitle files.
    public static let extensions = [
        "srt", "ass", "ssa", "vtt", "sub", "idx",
        "smi", "sami", "mpl", "txt", "pjs", "aqt", "jss", "rt", "sup"
    ]

    public static func isSubtitleURL(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }

    /// True when `subtitleURL` sits next to `mediaURL` with a sidecar-style name
    /// (`Video.srt`, `Video.en.srt`, `Video_en.srt`).
    public static func isAssociatedSidecar(_ subtitleURL: URL, of mediaURL: URL) -> Bool {
        guard mediaURL.isFileURL, subtitleURL.isFileURL else { return false }
        guard isSubtitleURL(subtitleURL) else { return false }

        let mediaDir = mediaURL.deletingLastPathComponent().standardizedFileURL
        let subDir = subtitleURL.deletingLastPathComponent().standardizedFileURL
        guard mediaDir == subDir else { return false }

        let baseName = mediaURL.deletingPathExtension().lastPathComponent
        let name = subtitleURL.deletingPathExtension().lastPathComponent
        return name == baseName
            || name.hasPrefix(baseName + ".")
            || name.hasPrefix(baseName + "_")
    }

    public static func findLocalSubtitles(for mediaURL: URL) -> [SubtitleMatch] {
        let directory = mediaURL.deletingLastPathComponent()
        let baseName = mediaURL.deletingPathExtension().lastPathComponent
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return [] }

        return files.compactMap { fileURL in
            let ext = fileURL.pathExtension.lowercased()
            guard extensions.contains(ext) else { return nil }
            // Prefer .idx for VobSub pairs; skip lone .sub when matching .idx exists.
            if ext == "sub" {
                let idx = fileURL.deletingPathExtension().appendingPathExtension("idx")
                if files.contains(idx) { return nil }
            }
            let name = fileURL.deletingPathExtension().lastPathComponent
            guard name == baseName || name.hasPrefix(baseName + ".") || name.hasPrefix(baseName + "_") else {
                return nil
            }
            let lang = extractLanguage(from: name, base: baseName)
            return SubtitleMatch(url: fileURL, label: fileURL.lastPathComponent, languageCode: lang)
        }
    }

    private static func extractLanguage(from name: String, base: String) -> String? {
        let remainder = name.dropFirst(base.count).trimmingCharacters(in: CharacterSet(charactersIn: "._"))
        return remainder.isEmpty ? nil : String(remainder)
    }

    public static func preferredMatch(
        from matches: [SubtitleMatch],
        preferredLanguage: String
    ) -> SubtitleMatch? {
        guard !matches.isEmpty else { return nil }
        let preferred = preferredLanguage.lowercased()
        if !preferred.isEmpty,
           let match = matches.first(where: {
               ($0.languageCode ?? "").lowercased().hasPrefix(preferred)
           }) {
            return match
        }
        if let english = matches.first(where: { ($0.languageCode ?? "").lowercased().hasPrefix("en") }) {
            return english
        }
        return matches.first
    }
}

public enum SubtitleLabels {
    public static func displayName(for track: Track) -> String {
        var parts: [String] = []

        if !track.title.isEmpty {
            parts.append(track.title)
        } else if let language = track.language, !language.isEmpty {
            parts.append(languageDisplayName(language))
        } else {
            parts.append("Track \(track.id)")
        }

        var badges: [String] = []
        if let codecBadge = track.codecBadge { badges.append(codecBadge) }
        if track.isDefault { badges.append("Default") }
        if track.isForced { badges.append("Forced") }
        if track.isLikelySDH { badges.append("SDH/CC") }
        if track.isExternal { badges.append("External") } else if track.kind == .subtitle {
            badges.append("Embedded")
        }

        if badges.isEmpty {
            return parts.joined(separator: " · ")
        }
        return "\(parts[0]) · \(badges.joined(separator: ", "))"
    }

    public static func displayName(for match: SubtitleMatch) -> String {
        if let language = match.languageCode, !language.isEmpty {
            return "\(match.label) · \(languageDisplayName(language))"
        }
        return match.label
    }

    public static func languageDisplayName(_ code: String) -> String {
        let normalized = code.replacingOccurrences(of: "_", with: "-")
        let locale = Locale.current
        if let name = locale.localizedString(forLanguageCode: normalized) {
            return name.capitalized
        }
        return normalized.uppercased()
    }

    public static func shortStatus(activeTrack: Track?) -> String {
        guard let activeTrack else { return "Off" }
        return displayName(for: activeTrack)
    }
}

public struct OnlineSubtitleResult: Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let languageCode: String
    public let languageLabel: String
    public let version: String
    public let source: String
    public let hearingImpaired: Bool
    public let isHD: Bool
    public let downloadCount: Int
    public let episodeTitle: String?

    public init(
        id: String,
        displayName: String,
        languageCode: String,
        languageLabel: String,
        version: String,
        source: String,
        hearingImpaired: Bool,
        isHD: Bool,
        downloadCount: Int,
        episodeTitle: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.languageCode = languageCode
        self.languageLabel = languageLabel
        self.version = version
        self.source = source
        self.hearingImpaired = hearingImpaired
        self.isHD = isHD
        self.downloadCount = downloadCount
        self.episodeTitle = episodeTitle
    }

    public var detailLine: String {
        var parts = [languageLabel, version, source]
        if isHD { parts.append("HD") }
        if hearingImpaired { parts.append("SDH") }
        if downloadCount > 0 { parts.append("\(downloadCount) downloads") }
        return parts.joined(separator: " · ")
    }
}

public enum OnlineSubtitleError: Error, LocalizedError {
    case invalidQuery
    case showNotFound(String)
    case noResults
    case temporarilyUnavailable
    case rateLimited
    case invalidResponse
    case downloadFailed(String)
    case sidecarWriteFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidQuery:
            return "Could not detect a TV episode from this filename."
        case .showNotFound(let name):
            return "No show matched “\(name)”."
        case .noResults:
            return "No subtitles found for this episode and language."
        case .temporarilyUnavailable:
            return "Subtitle catalog is refreshing. Try again in a moment."
        case .rateLimited:
            return "Too many requests. Wait a bit and try again."
        case .invalidResponse:
            return "Subtitle service returned an unexpected response."
        case .downloadFailed(let message):
            return message
        case .sidecarWriteFailed(let message):
            return message
        }
    }
}

/// Keyless TV subtitle search/download via Gestdown (Addic7ed-style).
public actor GestdownClient {
    private let session: URLSession
    private let baseURL = URL(string: "https://api.gestdown.info")!
    private let userAgent = "Kinema/1.0"

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func search(
        showTitle: String,
        season: Int,
        episode: Int,
        language: String
    ) async throws -> [OnlineSubtitleResult] {
        let languageCode = Self.normalizeLanguageCode(language)
        guard languageCode.count >= 2 else { throw OnlineSubtitleError.invalidQuery }

        let show = try await resolveShow(named: showTitle, season: season)
        let url = baseURL
            .appendingPathComponent("subtitles")
            .appendingPathComponent("get")
            .appendingPathComponent(show.id)
            .appendingPathComponent("\(season)")
            .appendingPathComponent("\(episode)")
            .appendingPathComponent(languageCode)
        let (data, response) = try await get(url: url)

        guard let http = response as? HTTPURLResponse else {
            throw OnlineSubtitleError.invalidResponse
        }
        switch http.statusCode {
        case 200:
            break
        case 404:
            throw OnlineSubtitleError.noResults
        case 423:
            throw OnlineSubtitleError.temporarilyUnavailable
        case 429:
            throw OnlineSubtitleError.rateLimited
        default:
            throw OnlineSubtitleError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(SubtitleSearchResponse.self, from: data)
        let episodeTitle = decoded.episode?.title
        let results = (decoded.matchingSubtitles ?? []).map { item in
            let version = item.version.isEmpty ? "Default" : item.version
            let display = [show.name, String(format: "S%02dE%02d", season, episode), version]
                .joined(separator: " · ")
            return OnlineSubtitleResult(
                id: item.subtitleId,
                displayName: display,
                languageCode: languageCode,
                languageLabel: item.language.isEmpty ? languageCode.uppercased() : item.language,
                version: version,
                source: item.source.isEmpty ? "Gestdown" : item.source,
                hearingImpaired: item.hearingImpaired,
                isHD: item.hd,
                downloadCount: item.downloadCount,
                episodeTitle: episodeTitle
            )
        }
        if results.isEmpty {
            throw OnlineSubtitleError.noResults
        }
        return results
    }

    public func download(_ result: OnlineSubtitleResult) async throws -> URL {
        let url = baseURL
            .appendingPathComponent("subtitles")
            .appendingPathComponent("download")
            .appendingPathComponent(result.id)
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (tempURL, response) = try await session.download(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw OnlineSubtitleError.downloadFailed("Could not download subtitle file.")
        }

        let suggested = suggestedFilename(from: response)
            ?? "\(Self.sanitizeFilenameComponent(result.version)).\(result.languageCode).srt"
        return try storeInCaches(tempURL: tempURL, suggestedName: suggested)
    }

    /// Writes a downloaded subtitle next to the media file as `{stem}.{lang}.srt` when possible.
    public nonisolated static func installSidecar(
        downloadedURL: URL,
        nextTo mediaURL: URL,
        languageCode: String,
        version: String
    ) throws -> URL {
        guard mediaURL.isFileURL else {
            throw OnlineSubtitleError.sidecarWriteFailed("Online save needs a local video file.")
        }

        let directory = mediaURL.deletingLastPathComponent()
        let stem = mediaURL.deletingPathExtension().lastPathComponent
        let lang = Self.normalizeLanguageCode(languageCode)
        let preferred = directory.appendingPathComponent("\(stem).\(lang).srt")
        let destination: URL
        if !FileManager.default.fileExists(atPath: preferred.path) {
            destination = preferred
        } else {
            let tag = Self.sanitizeFilenameComponent(version)
            destination = directory.appendingPathComponent("\(stem).\(lang).\(tag).srt")
        }

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: downloadedURL, to: destination)
            return destination
        } catch {
            throw OnlineSubtitleError.sidecarWriteFailed(
                "Could not save next to the video (\(error.localizedDescription))."
            )
        }
    }

    public nonisolated static func normalizeLanguageCode(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return "en" }
        let primary = trimmed
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? trimmed
        if primary.count == 2 || primary.count == 3 { return primary }
        // Best-effort for accidental full names typed in the field.
        switch primary {
        case "english": return "en"
        case "french", "francais", "français": return "fr"
        case "spanish", "espanol", "español": return "es"
        case "german", "deutsch": return "de"
        case "italian", "italiano": return "it"
        case "portuguese", "portugues", "português": return "pt"
        case "arabic": return "ar"
        case "persian", "farsi": return "fa"
        case "turkish": return "tr"
        case "russian": return "ru"
        case "chinese", "mandarin": return "zh"
        case "japanese": return "ja"
        case "korean": return "ko"
        default:
            return String(primary.prefix(2))
        }
    }

    private func resolveShow(named title: String, season: Int) async throws -> ShowDTO {
        let query = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 3 else { throw OnlineSubtitleError.invalidQuery }

        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? query
        guard let searchURL = URL(string: "https://api.gestdown.info/shows/search/\(encoded)") else {
            throw OnlineSubtitleError.invalidQuery
        }
        let (data, response) = try await get(url: searchURL)
        guard let http = response as? HTTPURLResponse else {
            throw OnlineSubtitleError.invalidResponse
        }
        switch http.statusCode {
        case 200:
            break
        case 404:
            throw OnlineSubtitleError.showNotFound(query)
        case 429:
            throw OnlineSubtitleError.rateLimited
        default:
            throw OnlineSubtitleError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(ShowSearchResponse.self, from: data)
        let shows = decoded.shows ?? []
        guard !shows.isEmpty else { throw OnlineSubtitleError.showNotFound(query) }

        return pickBestShow(from: shows, query: query, season: season)
    }

    /// Prefer exact title matches that include the requested season.
    /// Gestdown often returns multiple same-named shows (e.g. two "The Boys").
    private func pickBestShow(from shows: [ShowDTO], query: String, season: Int) -> ShowDTO {
        let normalizedQuery = normalizeMatchKey(query)

        func score(_ show: ShowDTO) -> (Int, Int, Int) {
            let exactName = normalizeMatchKey(show.name) == normalizedQuery ? 1 : 0
            let hasSeason: Int
            if let seasons = show.seasons, !seasons.isEmpty {
                hasSeason = seasons.contains(season) ? 1 : 0
            } else if let count = show.nbSeasons {
                hasSeason = count >= season ? 1 : 0
            } else {
                hasSeason = 0
            }
            // Prefer richer/more recent catalogs when titles collide.
            let richness = show.nbSeasons ?? show.seasons?.count ?? 0
            return (exactName, hasSeason, richness)
        }

        return shows.max { lhs, rhs in
            let left = score(lhs)
            let right = score(rhs)
            if left.0 != right.0 { return left.0 < right.0 }
            if left.1 != right.1 { return left.1 < right.1 }
            return left.2 < right.2
        } ?? shows[0]
    }

    private func get(url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await session.data(for: request)
    }

    private func storeInCaches(tempURL: URL, suggestedName: String) throws -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = caches.appendingPathComponent("KinemaSubtitles", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let safeName = suggestedName.isEmpty ? "download.srt" : Self.sanitizeFilenameComponent(suggestedName)
        let destination = folder.appendingPathComponent(safeName)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)
        return destination
    }

    private func suggestedFilename(from response: URLResponse) -> String? {
        guard let http = response as? HTTPURLResponse,
              let disposition = http.value(forHTTPHeaderField: "Content-Disposition") else {
            return nil
        }
        // filename="…" or filename*=UTF-8''…
        if let starRange = disposition.range(of: "filename*="),
           let value = disposition[starRange.upperBound...].split(separator: ";").first {
            var raw = String(value).trimmingCharacters(in: .whitespacesAndNewlines)
            if let encoded = raw.split(separator: "'", maxSplits: 2, omittingEmptySubsequences: false).last {
                raw = String(encoded)
            }
            raw = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if let decoded = raw.removingPercentEncoding, !decoded.isEmpty {
                return decoded
            }
        }
        if let range = disposition.range(of: "filename=") {
            var raw = String(disposition[range.upperBound...].split(separator: ";").first ?? "")
            raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            raw = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            return raw.isEmpty ? nil : raw
        }
        return nil
    }

    private nonisolated static func sanitizeFilenameComponent(_ value: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = value
            .components(separatedBy: illegal)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "subtitle" : cleaned
    }

    private func normalizeMatchKey(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private struct ShowSearchResponse: Decodable {
        let shows: [ShowDTO]?
    }

    private struct ShowDTO: Decodable {
        let id: String
        let name: String
        let nbSeasons: Int?
        let seasons: [Int]?
        let tmdbId: Int?
        let tvDbId: Int?
    }

    private struct SubtitleSearchResponse: Decodable {
        let matchingSubtitles: [SubtitleDTO]?
        let episode: EpisodeDTO?
    }

    private struct EpisodeDTO: Decodable {
        let title: String?
    }

    private struct SubtitleDTO: Decodable {
        let subtitleId: String
        let version: String
        let hearingImpaired: Bool
        let hd: Bool
        let language: String
        let downloadCount: Int
        let source: String
    }
}

public enum SubtitleStyling {
    public static func mpvOptions(
        fontSize: Int,
        fontName: String = "",
        colorHex: String = SubtitlePreferenceCatalog.defaultColorHex,
        encodingID: String = SubtitlePreferenceCatalog.defaultEncodingID,
        fontsDirectory: URL? = SubtitleFontRegistry.prepare()
    ) -> [String: String] {
        var options: [String: String] = [
            "sub-font-size": "\(fontSize)",
            "sub-border-size": "2",
            "sub-shadow-offset": "1",
            "sub-color": normalizedSubtitleColorHex(colorHex),
            "sub-border-color": "#FF000000",
            "sub-codepage": SubtitlePreferenceCatalog.encoding(id: encodingID).id
        ]
        if let fontsDirectory {
            options["sub-fonts-dir"] = fontsDirectory.path
        }
        if !fontName.isEmpty {
            options["sub-font"] = fontName
        }
        return options
    }
}
