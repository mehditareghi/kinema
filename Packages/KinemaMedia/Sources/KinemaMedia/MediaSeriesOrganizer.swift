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
}

public enum MediaSeriesOrganizer {
    private static let episodeRegex: NSRegularExpression = {
        let pattern = #"^(.+?)[\.\-_ ]*[Ss](\d{1,2})\s*[Ee](\d{1,2})(?:[\.\-_ ].*)?$"#
        return try! NSRegularExpression(pattern: pattern, options: [])
    }()

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
        let stem = url.deletingPathExtension().lastPathComponent
        let range = NSRange(stem.startIndex..., in: stem)
        guard let match = episodeRegex.firstMatch(in: stem, range: range),
              match.numberOfRanges >= 4,
              let showRange = Range(match.range(at: 1), in: stem),
              let seasonRange = Range(match.range(at: 2), in: stem),
              let episodeRange = Range(match.range(at: 3), in: stem) else { return nil }

        let showRaw = String(stem[showRange])
            .trimmingCharacters(in: CharacterSet(charactersIn: "._- "))
        guard !showRaw.isEmpty,
              let season = Int(stem[seasonRange]),
              let episode = Int(stem[episodeRange]) else { return nil }

        let showTitle = formatDisplayName(showRaw)
        let showKey = normalizeKey(showRaw)
        guard !showKey.isEmpty else { return nil }

        return ParsedEpisode(
            url: url,
            showKey: showKey,
            showTitle: showTitle,
            season: season,
            episode: episode
        )
    }

    private static func normalizeKey(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
