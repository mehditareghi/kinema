import Foundation

public enum VirtualBrowseSegment: Equatable, Sendable, Hashable {
    case show(key: String, title: String)
    case season(number: Int, showKey: String, showTitle: String)

    public var displayTitle: String {
        switch self {
        case .show(_, let title):
            return title
        case .season(let number, _, let showTitle):
            return "\(showTitle) \(Self.seasonLabel(number))"
        }
    }

    public static func seasonLabel(_ number: Int) -> String {
        String(format: "S%02d", number)
    }
}

public struct VirtualSeriesFolder: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let segment: VirtualBrowseSegment
    /// All titles rolled into this spotlight (episodes for the show / season).
    public let videoURLs: [URL]

    public init(id: String, title: String, segment: VirtualBrowseSegment, videoURLs: [URL] = []) {
        self.id = id
        self.title = title
        self.segment = segment
        self.videoURLs = videoURLs
    }
}

public struct SeriesBrowseContent: Sendable {
    public let virtualFolders: [VirtualSeriesFolder]
    public let videoURLs: [URL]

    public init(virtualFolders: [VirtualSeriesFolder], videoURLs: [URL]) {
        self.virtualFolders = virtualFolders
        self.videoURLs = videoURLs
    }

    public static let empty = SeriesBrowseContent(virtualFolders: [], videoURLs: [])
}

struct ParsedEpisode: Sendable, Equatable {
    let url: URL
    let showKey: String
    let showTitle: String
    let season: Int
    let episode: Int
    /// `nil` = main/unsplit file; `2` for `S01E00.Part2`, etc.
    let part: Int?

    var identity: MediaEpisodeIdentity {
        MediaEpisodeIdentity(showTitle: showTitle, season: season, episode: episode, part: part)
    }

    var episodeKey: String {
        "\(showKey)-s\(season)-e\(episode)"
    }
}

/// TV episode identity parsed from a media filename (`Show.S01E02…`).
public struct MediaEpisodeIdentity: Sendable, Equatable {
    public let showTitle: String
    public let season: Int
    public let episode: Int
    /// Multi-part suffix when present (`S01E00.Part2` → `2`); otherwise `nil`.
    public let part: Int?

    public var displayLabel: String {
        "\(showTitle) · \(seasonEpisodeCode)"
    }

    public var seasonEpisodeCode: String {
        let base = String(format: "S%02dE%02d", season, episode)
        guard let part else { return base }
        return "\(base) · Part \(part)"
    }

    public init(showTitle: String, season: Int, episode: Int, part: Int? = nil) {
        self.showTitle = showTitle
        self.season = season
        self.episode = episode
        self.part = part
    }
}

public enum MediaSeriesOrganizer {
    private static let episodeRegex: NSRegularExpression = {
        // Show.S01E02… / Show_S1E2… / Show 1x02…
        let pattern = #"^(.+?)[\.\-_ ]*(?:[Ss](\d{1,2})\s*[Ee](\d{1,2})|(\d{1,2})\s*[xX]\s*(\d{1,3}))(?:[\.\-_ ].*)?$"#
        return try! NSRegularExpression(pattern: pattern, options: [])
    }()

    private static let partRegex: NSRegularExpression = {
        let pattern = #"(?i)(?:^|[\.\-_ ])(?:part|pt)[\.\-_ ]*0*(\d+)"#
        return try! NSRegularExpression(pattern: pattern, options: [])
    }()

    private static let volumeEpisodeRegex: NSRegularExpression = {
        // Love Death Robots Vol 2 E03 / Volume.2.01
        let pattern = #"(?i)^(.+?)[\.\-_ ]+(?:vol|volume)[\.\-_ ]*(\d{1,2})[\.\-_ ]+(?:(?:e|ep|episode)[\.\-_ ]*)?(\d{1,3})(?:[\.\-_ ].*)?$"#
        return try! NSRegularExpression(pattern: pattern, options: [])
    }()

    private static let fillerKeyTokens = ["and", "the", "of", "an", "a"]

    /// Parses `Show.S01E02` / `Show_S1E2` / `Show 1x02` style stems from a media URL.
    public static func episodeIdentity(from url: URL) -> MediaEpisodeIdentity? {
        parseEpisode(from: url)?.identity
    }

    /// Stable key for matching catalog show titles to parsed filenames (`The Boys` → `theboys`).
    public static func showKey(forTitle title: String) -> String {
        normalizeKey(title)
    }

    /// Whether a parsed filename show title likely refers to the same series as a catalog title.
    public static func showTitleMatches(_ filenameShowTitle: String, catalogTitle: String) -> Bool {
        showKeysMatch(showKey(forTitle: filenameShowTitle), catalogTitle: catalogTitle)
    }

    /// Fuzzy show-key match for abbreviations (`ldr`), filler words (`and`), and near titles.
    public static func showKeysMatch(_ filenameKey: String, catalogTitle: String) -> Bool {
        let catalogKey = showKey(forTitle: catalogTitle)
        guard !filenameKey.isEmpty, !catalogKey.isEmpty else { return false }
        if filenameKey == catalogKey { return true }

        if stripFillerWords(fromKey: filenameKey) == stripFillerWords(fromKey: catalogKey) {
            return true
        }

        let acronym = acronymKey(forTitle: catalogTitle)
        if filenameKey.count >= 2, filenameKey.count <= acronym.count + 2, filenameKey == acronym {
            return true
        }

        let strippedFile = stripFillerWords(fromKey: filenameKey)
        let strippedCatalog = stripFillerWords(fromKey: catalogKey)
        let minLength = 8
        if strippedFile.count >= minLength, strippedCatalog.count >= minLength {
            if strippedFile.contains(strippedCatalog) || strippedCatalog.contains(strippedFile) {
                return true
            }
        }

        return false
    }

    /// Initials from a show title (`Love, Death & Robots` → `ldr`).
    public static func acronymKey(forTitle title: String) -> String {
        title.split { !$0.isLetter && !$0.isNumber }
            .filter { !$0.isEmpty }
            .compactMap { word in
                word.first.map { String($0).lowercased() }
            }
            .joined()
    }

    /// True when both URLs belong to the same parsed show.
    public static func isSameShow(lhs: URL, rhs: URL) -> Bool {
        guard let a = parseEpisode(from: lhs), let b = parseEpisode(from: rhs) else { return false }
        return a.showKey == b.showKey
    }

    /// Next title continues the same show later in season/episode/part order
    /// (e.g. `S01E00` → `S01E00.Part2` → `S01E01`).
    public static func seriesContinuation(from currentURL: URL, to nextURL: URL) -> MediaEpisodeIdentity? {
        guard let current = parseEpisode(from: currentURL),
              let next = parseEpisode(from: nextURL),
              current.showKey == next.showKey else { return nil }
        guard playbackOrder(next) > playbackOrder(current) else { return nil }
        return next.identity
    }

    /// Best following file of the same show after `currentURL` within `urls`.
    /// Orders by season → episode → part (`S01E00` then `S01E00.Part2` then `S01E01`).
    public static func nextEpisode(after currentURL: URL, in urls: [URL]) -> (url: URL, identity: MediaEpisodeIdentity)? {
        guard let current = parseEpisode(from: currentURL) else { return nil }
        let currentOrder = playbackOrder(current)

        let candidates: [ParsedEpisode] = urls.compactMap { url in
            guard let parsed = parseEpisode(from: url), parsed.showKey == current.showKey else { return nil }
            guard playbackOrder(parsed) > currentOrder else { return nil }
            return parsed
        }

        guard let best = candidates.min(by: { lhs, rhs in
            let lo = playbackOrder(lhs)
            let ro = playbackOrder(rhs)
            if lo != ro { return lo < ro }
            return lhs.url.lastPathComponent.localizedStandardCompare(rhs.url.lastPathComponent) == .orderedAscending
        }) else { return nil }

        return (best.url, best.identity)
    }

    /// Season → episode → part (`nil` / main file sorts before Part 2).
    private static func playbackOrder(_ episode: ParsedEpisode) -> (Int, Int, Int) {
        (episode.season, episode.episode, episode.part ?? 0)
    }

    public static func organize(
        videoURLs: [URL],
        virtualPath: [VirtualBrowseSegment]
    ) -> SeriesBrowseContent {
        let episodes = videoURLs.compactMap(parseEpisode(from:))
        let episodeURLs = Set(episodes.map(\.url))
        let looseURLs = videoURLs.filter { !episodeURLs.contains($0) }

        switch virtualPath.count {
        case 0:
            return organizeRoot(episodes: episodes, looseURLs: looseURLs)
        case 1:
            switch virtualPath[0] {
            case .show(let key, _):
                return organizeShowEpisodes(episodes.filter { $0.showKey == key })
            case .season(let season, let showKey, _):
                return seasonContent(episodes: episodes, showKey: showKey, season: season)
            }
        case 2:
            guard case .show(let key, _) = virtualPath[0],
                  case .season(let season, _, _) = virtualPath[1] else { return .empty }
            return seasonContent(episodes: episodes, showKey: key, season: season)
        default:
            break
        }
        return .empty
    }

    private static func seasonContent(
        episodes: [ParsedEpisode],
        showKey: String,
        season: Int
    ) -> SeriesBrowseContent {
        let seasonEpisodes = episodes
            .filter { $0.showKey == showKey && $0.season == season }
            .sorted { lhs, rhs in
                if lhs.episode != rhs.episode { return lhs.episode < rhs.episode }
                return lhs.url.lastPathComponent.localizedCaseInsensitiveCompare(rhs.url.lastPathComponent) == .orderedAscending
            }
        return SeriesBrowseContent(
            virtualFolders: [],
            videoURLs: seasonEpisodes.map(\.url)
        )
    }

    public static func formatDisplayName(_ raw: String) -> String {
        let replaced = raw
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        let collapsed = replaced
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return collapsed
            .split(separator: " ")
            .map { word in
                word.prefix(1).uppercased() + word.dropFirst().lowercased()
            }
            .joined(separator: " ")
    }

    private static func organizeRoot(episodes: [ParsedEpisode], looseURLs: [URL]) -> SeriesBrowseContent {
        let grouped = Dictionary(grouping: episodes, by: \.showKey)
        let shouldFlattenShow = grouped.count == 1 && looseURLs.isEmpty

        if shouldFlattenShow, let showEpisodes = grouped.values.first, let sample = showEpisodes.first {
            return organizeShowLevel(
                showTitle: sample.showTitle,
                showKey: sample.showKey,
                episodes: showEpisodes
            )
        }

        let virtualFolders = grouped.values
            .compactMap { episodes -> VirtualSeriesFolder? in
                guard let sample = episodes.first else { return nil }
                let urls = episodes.map(\.url).sorted {
                    $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
                }
                return VirtualSeriesFolder(
                    id: "show-\(sample.showKey)",
                    title: sample.showTitle,
                    segment: .show(key: sample.showKey, title: sample.showTitle),
                    videoURLs: urls
                )
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        return SeriesBrowseContent(
            virtualFolders: virtualFolders,
            videoURLs: looseURLs.sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }
        )
    }

    private static func organizeShowEpisodes(_ episodes: [ParsedEpisode]) -> SeriesBrowseContent {
        guard let sample = episodes.first else { return .empty }
        return organizeShowLevel(
            showTitle: sample.showTitle,
            showKey: sample.showKey,
            episodes: episodes
        )
    }

    private static func organizeShowLevel(
        showTitle: String,
        showKey: String,
        episodes: [ParsedEpisode]
    ) -> SeriesBrowseContent {
        let seasons = Dictionary(grouping: episodes, by: \.season)

        if seasons.count == 1, let onlySeason = seasons.values.first {
            let sorted = onlySeason.sorted { lhs, rhs in
                if lhs.episode != rhs.episode { return lhs.episode < rhs.episode }
                return lhs.url.lastPathComponent.localizedCaseInsensitiveCompare(rhs.url.lastPathComponent) == .orderedAscending
            }
            return SeriesBrowseContent(
                virtualFolders: [],
                videoURLs: sorted.map(\.url)
            )
        }

        let virtualFolders = seasons.keys.sorted().map { season in
            let seasonEpisodes = (seasons[season] ?? []).sorted { lhs, rhs in
                if lhs.episode != rhs.episode { return lhs.episode < rhs.episode }
                return lhs.url.lastPathComponent.localizedCaseInsensitiveCompare(rhs.url.lastPathComponent) == .orderedAscending
            }
            return VirtualSeriesFolder(
                id: "\(showKey)-s\(season)",
                title: "\(showTitle) \(VirtualBrowseSegment.seasonLabel(season))",
                segment: .season(number: season, showKey: showKey, showTitle: showTitle),
                videoURLs: seasonEpisodes.map(\.url)
            )
        }

        return SeriesBrowseContent(virtualFolders: virtualFolders, videoURLs: [])
    }

    private static func parseEpisode(from url: URL) -> ParsedEpisode? {
        parseStandardEpisode(from: url) ?? parseVolumeEpisode(from: url)
    }

    private static func parseStandardEpisode(from url: URL) -> ParsedEpisode? {
        let stem = url.deletingPathExtension().lastPathComponent
        let range = NSRange(stem.startIndex..., in: stem)
        guard let match = episodeRegex.firstMatch(in: stem, range: range),
              match.numberOfRanges >= 6,
              let showRange = Range(match.range(at: 1), in: stem) else { return nil }

        let season: Int
        let episode: Int
        let episodeEndIndex: String.Index
        if match.range(at: 2).location != NSNotFound,
           let seasonRange = Range(match.range(at: 2), in: stem),
           let episodeRange = Range(match.range(at: 3), in: stem) {
            guard let s = Int(stem[seasonRange]), let e = Int(stem[episodeRange]) else { return nil }
            season = s
            episode = e
            episodeEndIndex = episodeRange.upperBound
        } else if match.range(at: 4).location != NSNotFound,
                  let seasonRange = Range(match.range(at: 4), in: stem),
                  let episodeRange = Range(match.range(at: 5), in: stem) {
            guard let s = Int(stem[seasonRange]), let e = Int(stem[episodeRange]) else { return nil }
            season = s
            episode = e
            episodeEndIndex = episodeRange.upperBound
        } else {
            return nil
        }

        return makeParsedEpisode(
            url: url,
            stem: stem,
            showRaw: String(stem[showRange]),
            season: season,
            episode: episode,
            suffixStart: episodeEndIndex
        )
    }

    private static func parseVolumeEpisode(from url: URL) -> ParsedEpisode? {
        let stem = url.deletingPathExtension().lastPathComponent
        let range = NSRange(stem.startIndex..., in: stem)
        guard let match = volumeEpisodeRegex.firstMatch(in: stem, range: range),
              match.numberOfRanges >= 4,
              let showRange = Range(match.range(at: 1), in: stem),
              let seasonRange = Range(match.range(at: 2), in: stem),
              let episodeRange = Range(match.range(at: 3), in: stem),
              let season = Int(stem[seasonRange]),
              let episode = Int(stem[episodeRange]) else { return nil }

        return makeParsedEpisode(
            url: url,
            stem: stem,
            showRaw: String(stem[showRange]),
            season: season,
            episode: episode,
            suffixStart: episodeRange.upperBound
        )
    }

    private static func makeParsedEpisode(
        url: URL,
        stem: String,
        showRaw: String,
        season: Int,
        episode: Int,
        suffixStart: String.Index
    ) -> ParsedEpisode? {
        let trimmedShowRaw = showRaw.trimmingCharacters(in: CharacterSet(charactersIn: "._- "))
        guard !trimmedShowRaw.isEmpty else { return nil }

        let showTitle = formatDisplayName(trimmedShowRaw)
        let showKey = normalizeKey(trimmedShowRaw)
        guard !showKey.isEmpty else { return nil }

        let suffix = String(stem[suffixStart...])
        let part = parsePartNumber(in: suffix)

        return ParsedEpisode(
            url: url,
            showKey: showKey,
            showTitle: showTitle,
            season: season,
            episode: episode,
            part: part
        )
    }

    private static func parsePartNumber(in suffix: String) -> Int? {
        let trimmed = suffix.trimmingCharacters(in: CharacterSet(charactersIn: "._- "))
        guard !trimmed.isEmpty else { return nil }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = partRegex.firstMatch(in: trimmed, range: range),
              match.numberOfRanges >= 2,
              let partRange = Range(match.range(at: 1), in: trimmed),
              let part = Int(trimmed[partRange]),
              part > 0 else { return nil }
        return part
    }

    private static func normalizeKey(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func stripFillerWords(fromKey key: String) -> String {
        var result = key
        for token in fillerKeyTokens {
            result = result.replacingOccurrences(of: token, with: "")
        }
        return result
    }
}
